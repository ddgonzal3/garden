#!/bin/bash
# =============================================================================
# Build Garden
# =============================================================================
# Builds the Garden macOS app using xcodebuild.
# Regenerates the Xcode project from project.yml first if xcodegen is available.
#
# Usage:
#   ./build.sh              # Debug build (default)
#   ./build.sh --release    # Release build
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Parse flags
BUILD_CONFIG="Debug"
for arg in "$@"; do
  case "$arg" in
    --release) BUILD_CONFIG="Release" ;;
  esac
done

# Regenerate Xcode project if xcodegen is available and project.yml changed
if command -v xcodegen &>/dev/null; then
  PROJ_MTIME=$(stat -f %m project.yml 2>/dev/null || echo 0)
  XCODEPROJ_MTIME=$(stat -f %m Garden.xcodeproj/project.pbxproj 2>/dev/null || echo 0)
  if [ "$PROJ_MTIME" -gt "$XCODEPROJ_MTIME" ]; then
    echo "[build] project.yml changed — regenerating Xcode project..."
    xcodegen generate
  fi
fi

echo "[build] Building Garden ($BUILD_CONFIG)..."
xcodebuild \
  -project Garden.xcodeproj \
  -scheme Garden \
  -configuration "$BUILD_CONFIG" \
  build 2>&1 | tail -20

echo "[build] Done."
