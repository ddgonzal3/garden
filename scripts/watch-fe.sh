#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Kill any existing Garden instances
pkill -f "target/debug/garden" 2>/dev/null || true
sleep 0.3

echo "Starting Tauri dev mode (frontend hot-reload)..."
cargo tauri dev
