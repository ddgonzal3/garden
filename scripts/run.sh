#!/bin/bash
set -e
cd "$(dirname "$0")/.."

APP_BUNDLE="src-tauri/target/debug/bundle/macos/Garden.app"

# Kill any existing Garden instances (bundle + raw binary, debug + release)
PIDS=$(pgrep -f "target/debug/.*garden" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
  echo "Stopping previous instance..."
  kill $PIDS 2>/dev/null || true
  sleep 0.5
fi

echo "Building (debug)..."
cargo tauri build --debug --bundles app

echo "Launching..."
open "$APP_BUNDLE"
