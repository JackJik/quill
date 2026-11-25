#!/usr/bin/env python3
"""
Add a bulk autocorrect pack (common misspellings) to Quill's ``snippets.json``.

Each line of the source is ``misspelling->correction``. Entries land in the
``AutoCorrect`` group as word-triggered, case-insensitive snippets — the same
shape the TextExpander importer produces for autocorrect — so a typo is fixed
once you finish typing the word regardless of its capitalization.

Source precedence:
  * ``--source`` — a local file path OR an http(s) URL; otherwise
  * the default URL below (Wikipedia's machine-readable common-misspellings
    list). Network access is only used for the default/URL case.

The script is idempotent and safe to re-run: any abbreviation already present
in the store (in any group) is skipped, so it never creates duplicates and
never clobbers your own snippets. A timestamped ``.bak`` is written first.

Usage:
    scripts/add-autocorrect-pack.py                 # fetch default list
    scripts/add-autocorrect-pack.py --source list.txt
    scripts/add-autocorrect-pack.py --source https://example.com/typos.txt
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
QUILL_STORE = HOME / "Library/Application Support/Quill/snippets.json"
DEFAULT_SOURCE = (
    "https://en.wikipedia.org/w/index.php"
    "?title=Wikipedia:Lists_of_common_misspellings/For_machines&action=raw"
)

LINE_RE = re.compile(r"^\s*(\S[^-]*?)\s*->\s*(.+?)\s*$")
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z'\-]*$")


def read_source(source: str) -> str:
    if re.match(r"^https?://", source):
        req = urllib.request.Request(source, headers={"User-Agent": "quill-autocorrect/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read().decode("utf-8", "replace")
    return Path(source).read_text(encoding="utf-8", errors="replace")


def build_pack(text: str, existing_abbr: set[str], group: str, min_len: int):
    now = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pack, seen = [], set()
    stats = dict(multi=0, nonword=0, short=0, dup=0, same=0)
    for raw in text.splitlines():
        m = LINE_RE.match(raw)
        if not m:
            continue
        miss, corr = m.group(1).strip(), m.group(2).strip()
        if "," in corr or ";" in corr:            # ambiguous: several corrections
            stats["multi"] += 1; continue
        if not WORD_RE.match(miss):               # single word token only
            stats["nonword"] += 1; continue
        if len(miss) < min_len:                   # avoid short false triggers
            stats["short"] += 1; continue
        if miss.lower() == corr.lower():
            stats["same"] += 1; continue
        key = miss.lower()
        if key in existing_abbr or key in seen:
            stats["dup"] += 1; continue
        seen.add(key)
        pack.append({
            "id": str(uuid.uuid4()).upper(),
            "abbreviation": miss,
            "expansion": corr,
            "trigger": "word",
            "caseSensitive": False,
            "group": group,
            "enabled": True,
            "createdAt": now,
            "updatedAt": now,
        })
    return pack, stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=DEFAULT_SOURCE,
                    help="local file path or http(s) URL of a 'typo->fix' list")
    ap.add_argument("--store", type=Path, default=QUILL_STORE,
                    help="Path to Quill snippets.json")
    ap.add_argument("--group", default="AutoCorrect", help="target group name")
    ap.add_argument("--min-len", type=int, default=4,
                    help="skip misspellings shorter than this (default 4)")
    ap.add_argument("--dry-run", action="store_true", help="report, do not write")
    args = ap.parse_args()

    try:
        text = read_source(args.source)
    except Exception as e:
        print(f"error: could not read source {args.source!r}: {e}", file=sys.stderr)
        return 2

    store = json.loads(args.store.read_text()) if args.store.exists() else []
    existing_abbr = {s["abbreviation"].lower() for s in store}

    pack, stats = build_pack(text, existing_abbr, args.group, args.min_len)

    print(f"source: {args.source}")
    print(f"new corrections to add: {len(pack)}")
    print("  skipped — multi-correction:{multi}  non-word:{nonword} "
          " <{ml} chars:{short}  already-present:{dup}  no-op:{same}".format(ml=args.min_len, **stats))
    if pack:
        print("  samples:", [(p["abbreviation"], p["expansion"]) for p in pack[:6]])

    if args.dry_run or not pack:
        if not pack:
            print("nothing to add.")
        return 0

    bak = args.store.with_suffix(
        ".json.bak-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    if args.store.exists():
        bak.write_text(args.store.read_text())
    store.extend(pack)
    args.store.parent.mkdir(parents=True, exist_ok=True)
    args.store.write_text(json.dumps(store, indent=2, sort_keys=True) + "\n")
    print(f"✓ added {len(pack)} corrections to group {args.group!r}")
    print(f"  store: {args.store} (now {len(store)} snippets)")
    print(f"  backup: {bak}")
    print()
    print("Quit and relaunch Quill to pick up the new snippets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
