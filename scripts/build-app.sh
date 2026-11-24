#!/usr/bin/env bash
# Build Quill as a proper .app bundle.
# Works with either full Xcode (via `swift build`) or Command Line Tools only
# (via direct `swiftc` invocation).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Quill.app"
BIN_OUT="$ROOT/.build/release/Quill"

cd "$ROOT"

build_with_swiftpm() {
    swift build -c release
    [[ -x "$BIN_OUT" ]]
}

build_with_swiftc() {
    local sdk
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
    mkdir -p "$(dirname "$BIN_OUT")"
    # Pick an arch that matches the host.
    local arch
    arch="$(uname -m)"
    case "$arch" in
        arm64) target="arm64-apple-macos12.0" ;;
        x86_64) target="x86_64-apple-macos12.0" ;;
        *) target="x86_64-apple-macos12.0" ;;
    esac
    swiftc -O -sdk "$sdk" -target "$target" \
        -o "$BIN_OUT" \
        Sources/Quill/*.swift \
        -framework Cocoa -framework Carbon
}

echo "→ Trying SwiftPM build…"
if build_with_swiftpm 2>/dev/null; then
    echo "  SwiftPM build OK"
else
    echo "  SwiftPM unavailable (full Xcode not installed); falling back to swiftc"
    build_with_swiftc
fi

if [[ ! -x "$BIN_OUT" ]]; then
    echo "Build did not produce $BIN_OUT" >&2
    exit 1
fi

echo "→ Assembling bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_OUT" "$APP/Contents/MacOS/Quill"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "→ Ad-hoc codesign (so macOS keeps Accessibility grants attached)"
codesign --force --deep --sign - "$APP"

echo
echo "✓ Built $APP"
echo "  Launch:      open \"$APP\""
echo "  First run:   grant Accessibility in System Settings → Privacy & Security → Accessibility"
echo "  Storage:     ~/Library/Application Support/Quill/snippets.json"
