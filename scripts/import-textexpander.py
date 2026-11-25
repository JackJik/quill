#!/usr/bin/env python3
"""
Import TextExpander snippets into Quill's ``snippets.json``.

Accepts any of these sources:
  * a classic ``Settings.textexpander`` plist (``snippetsTE2`` / ``groupsTE2``);
  * a ``*.textexpanderbackup`` bundle (a directory of ``group_*.xml`` plists,
    as produced by TextExpander's "Save Backup"); or
  * a ``.zip`` containing either of the above.

Merges with the existing Quill store by default: a snippet whose
``(abbreviation, group)`` tuple already exists is updated in place, and others
are appended. Pass ``--replace`` to blow away the existing store.

Usage:
    scripts/import-textexpander.py <Settings.textexpander | *.textexpanderbackup | backup.zip> [--replace]
"""
from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
QUILL_STORE = HOME / "Library/Application Support/Quill/snippets.json"

# TextExpander abbreviationMode:
#   0 = expand inside words (acts immediately — autocorrect-style)
#   1 = at word beginning
#   2 = after non-alpha / word boundary (the "safe" default)
#
# Quill has two modes: "immediate" and "word". Map 0 -> immediate, 1/2 -> word.
TE_MODE_TO_QUILL = {0: "immediate", 1: "word", 2: "word"}

# XML 1.0 forbids most C0 control characters; TextExpander occasionally embeds
# them in snippet text, which makes expat choke. Strip them and retry.
_BAD_XML = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")


def iso(ts) -> str:
    if ts is None:
        return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if isinstance(ts, datetime):
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(ts)


def _load_plist(raw: bytes) -> dict:
    try:
        return plistlib.loads(raw)
    except Exception:
        cleaned = _BAD_XML.sub("", raw.decode("utf-8", "replace"))
        return plistlib.loads(cleaned.encode("utf-8"))


def collect_raw(path: Path) -> list[tuple[dict, str]]:
    """Return a list of (snippet_plist, group_name) from any supported source."""
    # A zip: extract to a temp dir and recurse.
    if path.is_file() and zipfile.is_zipfile(path):
        with tempfile.TemporaryDirectory() as td:
            with zipfile.ZipFile(path) as zf:
                dest = Path(td)
                for member in zf.namelist():
                    # zip-slip guard
                    target = (dest / member).resolve()
                    if not str(target).startswith(str(dest.resolve())):
                        continue
                    zf.extract(member, dest)
            return collect_raw(dest)

    # A directory (incl. a *.textexpanderbackup bundle): gather group_*.xml.
    if path.is_dir():
        out: list[tuple[dict, str]] = []
        group_files = sorted(path.rglob("group_*.xml"))
        if group_files:
            for gf in group_files:
                d = _load_plist(gf.read_bytes())
                name = d.get("name") or "Imported"
                for s in (d.get("snippetPlists") or []):
                    out.append((s, name))
            return out
        # Fall back to a Settings.textexpander found inside the directory.
        for cand in path.rglob("Settings.textexpander"):
            out.extend(collect_raw(cand))
        return out

    # A single file: classic plist, or one exported group file.
    d = _load_plist(path.read_bytes())
    if "snippetsTE2" in d:
        uuid_to_group: dict[str, str] = {}
        for g in d.get("groupsTE2") or []:
            gname = g.get("name", "Imported")
            for u in g.get("snippetUUIDs") or []:
                uuid_to_group[u] = gname
        return [(s, uuid_to_group.get(s.get("uuidString", ""), "Imported"))
                for s in (d.get("snippetsTE2") or [])]
    if "snippetPlists" in d:
        name = d.get("name") or "Imported"
        return [(s, name) for s in d.get("snippetPlists") or []]
    return []


def convert(path: Path):
    raw = collect_raw(path)

    out: list[dict] = []
    skipped_no_text = 0
    skipped_no_abbr = 0
    non_text_types = 0

    for s, group in raw:
        abbr = (s.get("abbreviation") or "").strip()
        plain = s.get("plainText") or ""
        if not abbr:
            skipped_no_abbr += 1
            continue
        if not plain:
            skipped_no_text += 1
            continue

        if s.get("snippetType", 0) not in (0, 1):
            # Script / URL / AppleScript — Quill doesn't execute, but keep the
            # plainText (which TextExpander typically also populates).
            non_text_types += 1

        mode = TE_MODE_TO_QUILL.get(s.get("abbreviationMode", 2), "word")

        try:
            sid = str(uuid.UUID(s.get("uuidString", ""))).upper()
        except (ValueError, TypeError):
            sid = str(uuid.uuid4()).upper()

        out.append({
            "id": sid,
            "abbreviation": abbr,
            "expansion": plain,
            "trigger": mode,
            "caseSensitive": False,   # TE's IgnoreCase is on globally
            "group": group,
            "enabled": True,
            "createdAt": iso(s.get("creationDate")),
            "updatedAt": iso(s.get("modificationDate")),
        })

    return out, {
        "converted": len(out),
        "skipped_no_text": skipped_no_text,
        "skipped_no_abbr": skipped_no_abbr,
        "non_text_types_flagged": non_text_types,
    }


def merge(existing: list[dict], incoming: list[dict]) -> tuple[list[dict], int, int]:
    index: dict[tuple[str, str], int] = {}
    for i, s in enumerate(existing):
        key = (s["abbreviation"].lower(), s["group"].lower())
        index[key] = i

    added = updated = 0
    for s in incoming:
        key = (s["abbreviation"].lower(), s["group"].lower())
        if key in index:
            orig = existing[index[key]]
            s["id"] = orig["id"]
            s["createdAt"] = orig.get("createdAt", s["createdAt"])
            existing[index[key]] = s
            updated += 1
        else:
            existing.append(s)
            index[key] = len(existing) - 1
            added += 1
    return existing, added, updated


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path,
                    help="Settings.textexpander, *.textexpanderbackup bundle, or .zip")
    ap.add_argument("--replace", action="store_true",
                    help="Replace existing Quill snippets instead of merging")
    ap.add_argument("--store", type=Path, default=QUILL_STORE,
                    help="Path to Quill snippets.json")
    args = ap.parse_args()

    if not args.source.exists():
        print(f"error: {args.source} does not exist", file=sys.stderr)
        return 2

    incoming, stats = convert(args.source)
    if not incoming:
        print("error: no snippets with abbreviations found in that source",
              file=sys.stderr)
        return 1

    args.store.parent.mkdir(parents=True, exist_ok=True)
    if args.replace or not args.store.exists():
        final, added, updated = incoming, len(incoming), 0
    else:
        with args.store.open("r", encoding="utf-8") as f:
            existing = json.load(f)
        final, added, updated = merge(existing, incoming)

    with args.store.open("w", encoding="utf-8") as f:
        json.dump(final, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"✓ Imported {stats['converted']} snippets from TextExpander")
    print(f"  added:   {added}")
    print(f"  updated: {updated}")
    if stats["skipped_no_text"]:
        print(f"  skipped (no plainText): {stats['skipped_no_text']}")
    if stats["skipped_no_abbr"]:
        print(f"  skipped (no abbreviation): {stats['skipped_no_abbr']}")
    if stats["non_text_types_flagged"]:
        print(f"  non-text snippets imported as plain text: {stats['non_text_types_flagged']}")
    print(f"  store: {args.store}")
    print()
    print("Quit and relaunch Quill to pick up the new snippets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
