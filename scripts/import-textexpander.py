#!/usr/bin/env python3
"""
Convert a TextExpander ``Settings.textexpander`` file into Quill's
``snippets.json``.  Merges with the existing Quill store by default: a snippet
whose ``(abbreviation, group)`` tuple already exists is updated in place, and
others are appended.  Pass ``--replace`` to blow away the existing store.

Usage:
    scripts/import-textexpander.py <path/to/Settings.textexpander> [--replace]
"""
from __future__ import annotations

import argparse
import json
import plistlib
import sys
import uuid
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


def iso(ts) -> str:
    if ts is None:
        return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if isinstance(ts, datetime):
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return str(ts)


def convert(settings_path: Path) -> list[dict]:
    with settings_path.open("rb") as f:
        te = plistlib.load(f)

    snippets = te.get("snippetsTE2") or []
    groups = te.get("groupsTE2") or []

    uuid_to_group: dict[str, str] = {}
    for g in groups:
        name = g.get("name", "Imported")
        for u in g.get("snippetUUIDs") or []:
            uuid_to_group[u] = name

    out: list[dict] = []
    skipped_no_text = 0
    skipped_no_abbr = 0
    non_text_types = 0

    for s in snippets:
        abbr = (s.get("abbreviation") or "").strip()
        plain = s.get("plainText") or ""
        if not abbr:
            skipped_no_abbr += 1
            continue
        if not plain:
            skipped_no_text += 1
            continue

        stype = s.get("snippetType", 0)
        if stype not in (0, 1):
            # Script / URL / AppleScript — Quill doesn't execute, but keep
            # the plainText (which TextExpander typically also populates) and
            # flag the group.
            non_text_types += 1

        mode = TE_MODE_TO_QUILL.get(s.get("abbreviationMode", 2), "word")
        group = uuid_to_group.get(s.get("uuidString", ""), "Imported")

        # Reuse TextExpander's UUID when we can — makes re-imports idempotent.
        try:
            sid = str(uuid.UUID(s.get("uuidString", ""))).upper()
        except (ValueError, TypeError):
            sid = str(uuid.uuid4()).upper()

        out.append({
            "id": sid,
            "abbreviation": abbr,
            "expansion": plain,
            "trigger": mode,
            "caseSensitive": False,   # TE's IgnoreCase is on globally in this file
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
            # keep existing id so references in the file pane stay stable
            orig = existing[index[key]]
            s["id"] = orig["id"]
            s["createdAt"] = orig.get("createdAt", s["createdAt"])
            existing[index[key]] = s
            updated += 1
        else:
            existing.append(s)
            added += 1
    return existing, added, updated


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("settings", type=Path,
                    help="Path to TextExpander Settings.textexpander")
    ap.add_argument("--replace", action="store_true",
                    help="Replace existing Quill snippets instead of merging")
    ap.add_argument("--store", type=Path, default=QUILL_STORE,
                    help="Path to Quill snippets.json (default: ~/Library/Application Support/Quill/snippets.json)")
    args = ap.parse_args()

    if not args.settings.exists():
        print(f"error: {args.settings} does not exist", file=sys.stderr)
        return 2

    incoming, stats = convert(args.settings)

    args.store.parent.mkdir(parents=True, exist_ok=True)
    if args.replace or not args.store.exists():
        final = incoming
        added, updated = len(incoming), 0
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
