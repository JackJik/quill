# Quill

A **local-only** macOS text expander. Built as a drop-in replacement for TextExpander after they discontinued the pure-local tier and started forcing accounts into their cloud. No account, no sync server, no telemetry, no network calls at all. Snippets live in a single JSON file under `~/Library/Application Support/Quill/`.

## What it does

- Watches the keyboard globally for abbreviations you've defined.
- When one matches, deletes what you typed and types the expansion in its place.
- Lives in the menu bar (no Dock icon, no main window unless you open the editor).
- Supports two trigger modes per snippet:
  - **On word boundary** — expand when the character after the abbreviation is a space, punctuation, or return. This is the safe default.
  - **Immediately** — expand the moment the abbreviation is typed.
- Template variables: `{{date}}`, `{{time}}`, `{{longdate}}`, `{{clipboard}}`.
- Groups, per-snippet enable/disable, case-sensitive matching.

## What it deliberately does *not* do

- **No cloud sync.** If you want backup, put the JSON file in your own Dropbox / iCloud / Git repo yourself.
- **No account, no login, no "team" features.**
- **No analytics, no crash reporting, no update checks.**
- **No network code at all.** The binary doesn't link anything that would originate a connection.

## Build

Requires Xcode command-line tools (Swift 5.7+). From the repo root:

```bash
./scripts/build-app.sh
open Quill.app
```

The first launch will prompt for **Accessibility permission** — Quill needs it to watch for keystrokes and to type the expansions. Grant it in **System Settings → Privacy & Security → Accessibility**, then quit and relaunch Quill.

## Where snippets live

```
~/Library/Application Support/Quill/snippets.json
```

Pretty-printed, sorted keys, ISO-8601 dates — easy to diff and keep under version control if you want. The menu bar has a **Reveal snippets file in Finder** item.

## Importing snippets

Two helpers under `scripts/` bring snippets in from outside. Both merge into
your store and write a backup first, so they are safe to re-run.

### From TextExpander

`scripts/import-textexpander.py` imports a TextExpander export or backup:

```bash
scripts/import-textexpander.py "~/Desktop/TextExpander Backup.textexpanderbackup"
```

It accepts any of:

- a classic `Settings.textexpander` plist,
- a `*.textexpanderbackup` bundle — the folder TextExpander's **Save Backup**
  produces (a set of `group_*.xml` files), or
- a `.zip` of either (detected by content, so a missing `.zip` extension is fine).

Snippets keep their group names, and TextExpander's abbreviation modes map to
Quill's `word` / `immediate` triggers. Entries with no abbreviation
(TextExpander "suggestions") are skipped, since Quill triggers only on
abbreviations. Pass `--replace` to overwrite the store instead of merging.

### Bulk autocorrect (common misspellings)

`scripts/add-autocorrect-pack.py` adds a large set of `misspelling -> correction`
pairs to an `AutoCorrect` group (word-triggered, case-insensitive):

```bash
scripts/add-autocorrect-pack.py                      # fetch the default list
scripts/add-autocorrect-pack.py --source typos.txt   # or your own file / URL
```

With no `--source` it fetches Wikipedia's machine-readable common-misspellings
list (~4,000 entries). That fetch is the **only** network access anywhere in
this repo, it lives in a one-off script and never in the app, and passing a
local path or URL to `--source` avoids it entirely. The script is idempotent —
any abbreviation already in your store is skipped, so re-running adds nothing.
Other flags: `--dry-run`, `--group`, `--min-len`, `--store`.

After any import, quit and relaunch Quill (it also loads them on next launch)
to pick up the new snippets.

## How it works (so you can audit it before trusting it)

- `KeystrokeMonitor` uses `CGEventTap` at the session level to observe `keyDown` events only. The tap is `listenOnly`, so it cannot modify or suppress the user's keystrokes — Quill only *reads* them and separately injects its own events when it decides to expand.
- `Matcher` keeps a 128-character rolling buffer. On every printable character it checks whether the tail of the buffer equals any enabled abbreviation.
- `Replacer` injects backspaces to delete the typed abbreviation, then uses `CGEvent.keyboardSetUnicodeString` to type the expansion. This path **never touches the system clipboard**.
- Nothing is logged or persisted beyond the snippets file.

## Menu bar

- **Pause / Resume expansion** — toggle off when you're pairing or demoing.
- **Edit snippets…** — opens the editor window.
- **Reveal snippets file in Finder** — for backup, diff, sync.
- **Quit Quill** — stops the event tap and exits.

## Default snippets

Seeded on first run (edit or delete freely):

| Abbreviation | Expansion |
|---|---|
| `;sig` | your signature block |
| `;ddate` | today's date (immediate) |
| `;ttime` | current time (immediate) |
| `;email` | `info@tglabs.com` |

## License

Internal to 50mm LLC / TG Labs.
