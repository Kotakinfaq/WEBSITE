#!/usr/bin/env bash
# Builds Koan.app into ./build. Usage: scripts/build-app.sh [release|debug]
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Koan.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Koan" "$APP/Contents/MacOS/Koan"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS will run it and grant camera/mic prompts.
codesign --force --sign - "$APP"

echo "Built $APP"
