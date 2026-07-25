#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BIN=.build/release/WindowsSwitcher
APP=WindowsSwitcher.app

if [ ! -f "$BIN" ]; then
    echo "Release binary not found. Run: swift build -c release" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/WindowsSwitcher"
cp Info.plist "$APP/Contents/Info.plist"
echo "Built $APP"
