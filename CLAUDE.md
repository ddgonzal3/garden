# Garden

A macOS Tauri desktop task manager (React + Vite frontend, Rust backend).

## Design Principles

**Clean, calm, minimal.** Every UI decision should reduce visual noise, not add it. Prefer subtle over loud, native over custom, invisible over decorative. The app should feel like a quiet tool that stays out of the way — no unnecessary borders, badges, colors, or motion. Interactions should be immediate and direct (inline editing, drag-and-drop) rather than modal or multi-step. When in doubt, remove.

## Architecture

- **UI**: React + Vite, dark theme, L2C "Rich Edge" card styling
- **State**: React useState in App component, derived via backlog query functions
- **Persistence**: Per-project JSON files at `~/.garden/projects/<uuid>.json`, state at `~/.garden/state.json`
- **Desktop**: Tauri v2 with fs plugin for filesystem access scoped to `~/.garden/`

## Build & Run

```bash
./scripts/watch-fe.sh   # Dev mode: debug build + Vite hot-reload (CSS/TSX changes are instant)
./scripts/run.sh        # Debug build + launch .app
./scripts/release.sh    # Release build + launch .app (optimized)
./scripts/reload.sh     # Smart reload: triggers webview reload if watcher running, else falls back to run.sh
```

**For design iteration**, use `watch-fe.sh` — it runs `cargo tauri dev` so frontend changes reflect instantly without restarting.

**To use the app**, use `run.sh` (debug, faster compile) or `release.sh` (optimized).

**Never run `cargo tauri build` without `--bundles app`** unless you want a DMG.

## After Making Changes

**When `watch-fe.sh` is running**, most CSS/TSX changes hot-reload automatically. If you need a full page refresh, run:

```bash
./scripts/reload.sh
```

This detects the Vite dev server and triggers a webview reload via `curl http://localhost:5173/__reload`. If no dev server is running, it falls back to `./scripts/run.sh` (full debug build + relaunch).

**Always run `./scripts/reload.sh` after finishing a set of changes** so the user can see the result immediately.

## Conventions

- Items are ordered by `priority` (lower = higher in list) within their `priorityBucket` (0 = P1, 1 = P2, etc.)
- Categories are stored as ordered string arrays on each project
- All mutations go through `mutateActiveProject` which triggers auto-save via useEffect
- Project files are named by UUID to prevent slug collisions
