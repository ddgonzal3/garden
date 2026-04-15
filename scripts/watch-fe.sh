#!/bin/bash
set -e
cd "$(dirname "$0")/.."

APP_BINARY="src-tauri/target/debug/garden"

# Kill any existing Garden instance from this repo's build
if [ -f "$APP_BINARY" ]; then
  PIDS=$(pgrep -f "$PWD/$APP_BINARY" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Stopping previous instance..."
    kill $PIDS 2>/dev/null || true
    sleep 0.3
  fi
fi

echo "Starting Tauri dev mode (frontend hot-reload)..."
cargo tauri dev
