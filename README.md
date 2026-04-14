# Garden

A personal task manager for macOS. Native SwiftUI app with a crisp, clean UI.

You plant things, tend to them, some grow into priorities, some you prune. Tasks are flexible — they move around as priorities shift. Claude hooks into the same data file to categorize, reorganize, and help you decide what to work on next.

## How it works

- **Data:** JSON file at `~/.garden/backlog.json`. Categories, priority ordering, descriptions, metadata.
- **App:** Native SwiftUI Mac app. Sidebar for categories (customizable), main area shows tasks in priority order. Drag to reorder.
- **Claude integration:** Claude reads and writes the same JSON file. Say "add a task" or "reorganize my backlog" and it modifies the file directly. The app watches the file and live-reloads.

## Build

```bash
xcodebuild -project Garden.xcodeproj -scheme Garden -configuration Debug build
```
