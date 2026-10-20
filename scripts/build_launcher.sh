#!/bin/bash
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
out="${1:-$root/build/APK VR Library.app}"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
cp "$root/launcher/Info.plist" "$out/Contents/Info.plist"
cp "$root/launcher/app-resources/"* "$out/Contents/Resources/"
xcrun swiftc -O -target arm64-apple-macos15.0 -module-cache-path "${TMPDIR:-/tmp}/apkvr-module-cache" "$root/launcher/main.swift" -o "$out/Contents/MacOS/APKLibrary"
xattr -cr "$out"
codesign --force -s - "$out"
