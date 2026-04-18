#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Kill any existing Garden instances (bundle + raw binary, debug + release)
PIDS=$(pgrep -f "target/(debug|release)/.*garden" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
  echo "Stopping previous instance..."
  kill $PIDS 2>/dev/null || true
  sleep 0.3
fi

echo "Starting Tauri dev mode (frontend hot-reload)..."
cargo tauri dev
