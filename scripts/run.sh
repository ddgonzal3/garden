#!/bin/bash
# =============================================================================
# Build & Run Garden
# =============================================================================
# Builds the app, then launches it. Kills any existing instance first.
#
# Usage:
#   ./run.sh              # Debug build + run (default)
#   ./run.sh --release    # Release build + run
#   ./run.sh --no-build   # Just run the last build (skip build step)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Parse flags
SKIP_BUILD=false
BUILD_CONFIG="Debug"
for arg in "$@"; do
  case "$arg" in
    --no-build) SKIP_BUILD=true ;;
    --release)  BUILD_CONFIG="Release" ;;
  esac
done

# Find the built app
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
APP_PATH=$(find "$DERIVED_DATA" -path "*/Garden-*/Build/Products/$BUILD_CONFIG/Garden.app" -maxdepth 5 2>/dev/null | head -1)

if [ "$SKIP_BUILD" = false ]; then
  "$SCRIPT_DIR/build.sh" ${BUILD_CONFIG:+--$(echo "$BUILD_CONFIG" | tr '[:upper:]' '[:lower:]')}

  # Re-find after build
  APP_PATH=$(find "$DERIVED_DATA" -path "*/Garden-*/Build/Products/$BUILD_CONFIG/Garden.app" -maxdepth 5 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Garden.app not found in DerivedData."
  echo "Run ./scripts/build.sh first."
  exit 1
fi

# Kill existing instance
pkill -x Garden 2>/dev/null || true
sleep 0.5

echo "[run] Opening $APP_PATH..."
if [ -n "$GARDEN_ANTHROPIC_KEY" ]; then
  # Launch directly so env vars pass through (open doesn't forward them)
  "$APP_PATH/Contents/MacOS/Garden" &
  disown
else
  open "$APP_PATH"
fi
