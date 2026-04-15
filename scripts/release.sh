#!/bin/bash
set -e
cd "$(dirname "$0")/.."

APP_BUNDLE="src-tauri/target/release/bundle/macos/Garden.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Garden"

# Kill any existing Garden instance from this build
if [ -f "$APP_BINARY" ]; then
  PIDS=$(pgrep -f "$APP_BINARY" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Stopping previous instance..."
    kill $PIDS 2>/dev/null || true
    sleep 0.5
  fi
fi

echo "Building (release)..."
cargo tauri build --bundles app

echo "Launching..."
open "$APP_BUNDLE"
