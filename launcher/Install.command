#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ "$(uname -m)" != arm64 ]]; then
  echo "This release requires an Apple Silicon Mac."
  exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 26 )); then
  echo "This binary release requires macOS 26 or later."
  exit 1
fi
if [[ ! -x /opt/homebrew/bin/python3 ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    /opt/homebrew/bin/brew install python
  else
    echo "Install Homebrew from https://brew.sh, then run this installer again."
    exit 1
  fi
fi
if [[ ! -f "$HOME/Library/Application Support/MoltenVR/bin/libmoltenvr_openxr.dylib" ]]; then
  echo "Install and open MoltenVR first, then run this installer again."
  exit 1
fi
/opt/homebrew/bin/python3 verify_release.py
# The user explicitly runs this installer for this downloaded application.
# Remove quarantine only from this package, without changing system settings.
xattr -dr com.apple.quarantine . 2>/dev/null || true
open 'APK VR Library.app'
echo "Ready. Connect your Quest in MoltenVR and choose your games folder."
