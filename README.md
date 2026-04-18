# Garden

Personal task manager for macOS. Tauri desktop app (React + Vite frontend, Rust backend) with a clean, garden-themed UI.

You plant things, tend to them, some grow into priorities, some you prune. Tasks move around as priorities shift.

## How it works

- **Data:** per-project JSON at `~/.garden/projects/<uuid>.json`; active-project state at `~/.garden/state.json`
- **UI:** priority board with drag/drop reorder, per-card notes modal, inline rename, category color picker
- **Desktop:** Tauri v2 with `fs` plugin scoped to `~/.garden/`, native macOS vibrancy sidebar

## Build & Run

```bash
./scripts/debug.sh      # dev: debug build + Vite HMR
./scripts/run.sh        # debug build + launch .app
./scripts/release.sh    # optimized release build
./scripts/reload.sh     # smart reload (webview or full rebuild)
```

Never run `cargo tauri build` without `--bundles app` unless you want a DMG.
