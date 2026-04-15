#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# If Vite dev server is running, trigger a webview reload.
# Otherwise fall back to full debug build + relaunch.
if lsof -i :5173 -sTCP:LISTEN -t >/dev/null 2>&1; then
  curl -s http://localhost:5173/__reload >/dev/null
  echo "Reloaded."
else
  echo "No dev server — running full build..."
  exec ./scripts/run.sh
fi
