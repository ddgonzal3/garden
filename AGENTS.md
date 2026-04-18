# Garden

A native macOS SwiftUI task manager with Codex AI integration.

## Design Principles

**Clean, calm, minimal.** Every UI decision should reduce visual noise, not add it. Prefer subtle over loud, native over custom, invisible over decorative. The app should feel like a quiet tool that stays out of the way — no unnecessary borders, badges, colors, or motion. Interactions should be immediate and direct (inline editing, drag-and-drop) rather than modal or multi-step. When in doubt, remove.

## Architecture

- **UI**: SwiftUI, native macOS components, no external UI frameworks
- **State**: `BacklogStore` (ObservableObject) as single source of truth
- **Persistence**: JSON file at `~/.garden/backlog.json`, atomic writes, file watching for external sync
- **AI**: `AgentService` talks to Codex API with tool-use for backlog mutations

## Build & Run

After making changes, build and launch the app:
```bash
./scripts/run.sh
```
This builds, kills any existing instance, and opens the app in the foreground.

## Conventions

- Items are ordered by `priority` (lower = higher in list) within their `priorityBucket` (0 = P1, 1 = P2, etc.)
- Categories are stored as ordered string arrays on each project
- All mutations go through BacklogStore methods which call `save()` at the end
- File watcher debounces to avoid reload loops after app's own writes
