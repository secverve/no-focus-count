#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$PROJECT_DIR/.build/manual-release"
APP_DIR="$PROJECT_DIR/dist/NoFocusCount.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

/bin/rm -rf "$BUILD_DIR" "$APP_DIR"
/bin/mkdir -p "$BUILD_DIR" "$MACOS_DIR"

swiftc \
  -O \
  -parse-as-library \
  "$PROJECT_DIR/Sources/NoFocusCount/ActivityMonitor.swift" \
  "$PROJECT_DIR/Sources/NoFocusCount/AppModel.swift" \
  "$PROJECT_DIR/Sources/NoFocusCount/ContentView.swift" \
  "$PROJECT_DIR/Sources/NoFocusCount/Models.swift" \
  "$PROJECT_DIR/Sources/NoFocusCount/NoFocusCountApp.swift" \
  "$PROJECT_DIR/Sources/NoFocusCount/SessionRepository.swift" \
  -o "$MACOS_DIR/NoFocusCount"

/bin/cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "$APP_DIR"
