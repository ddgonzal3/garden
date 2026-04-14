# Projects in Garden

## Overview

Add a "project" layer above categories. Each project contains its own categories and items. A project switcher in the sidebar lets the user focus on one project at a time. All views (All, categories, Completed) are scoped to the active project.

Everything currently in Garden migrates automatically into a project named "Flow."

## Data Model

### New: `GardenProject`

```swift
struct GardenProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var categories: [String]       // ordered, same as today
    var items: [GardenItem]        // same struct, unchanged

    init(
        id: UUID = UUID(),
        name: String,
        categories: [String] = ["Uncategorized"],
        items: [GardenItem] = []
    )
}
```

Query methods currently on `Backlog` move here:
- `activeItems: [GardenItem]` — non-completed, sorted by priority
- `completedItems: [GardenItem]` — completed, sorted by completedAt desc
- `items(in category: String) -> [GardenItem]` — active items in a category

### Changed: `Backlog`

```swift
struct Backlog: Codable {
    var projects: [GardenProject]
    var activeProjectId: UUID?

    var activeProject: GardenProject? {
        projects.first { $0.id == activeProjectId } ?? projects.first
    }

    mutating func activeProjectIndex() -> Int? {
        if let id = activeProjectId {
            return projects.firstIndex { $0.id == id }
        }
        return projects.indices.first
    }
}
```

### Unchanged: `GardenItem`

No changes. The `category: String` field still identifies which category within the owning project. No `project` field needed — items are structurally nested inside their project.

### JSON Structure (after migration)

```json
{
  "projects": [
    {
      "id": "...",
      "name": "Flow",
      "categories": ["Uncategorized", "Variations", "Clip Editor", ...],
      "items": [...]
    }
  ],
  "activeProjectId": "..."
}
```

## Migration

Custom `init(from decoder:)` on `Backlog`:

1. Try decoding `projects` key (new format). If found, use it.
2. If not found, look for top-level `categories` and `items` (old format). Wrap them into a single `GardenProject` named "Flow". Set `activeProjectId` to that project's ID.
3. Save immediately to persist the migration.

This is a one-time, automatic, zero-interaction migration.

## UI Changes

### Sidebar (`SidebarView`)

Add a project switcher at the top of the sidebar, above the "All" row:

- **Picker** (menu style) showing the active project name
- Changing the selection updates `backlogStore.backlog.activeProjectId` and saves
- Below the picker: a small "+" button or menu item to add a new project
- Context menu on projects in the picker for rename/delete

The rest of the sidebar is unchanged — "All", categories, "Completed" — all automatically scoped to the active project because `BacklogStore` exposes project-scoped data.

### ContentView

- Add `selectedProject` state that syncs with `backlogStore.backlog.activeProjectId`
- When project changes, reset `selectedCategory` to nil (show "All" for the new project)

### AllItemsView

Currently iterates `store.backlog.categories` and `store.backlog.items(in:)`. Change to use the active project's categories and items.

### CategoryDetailView

Currently calls `store.backlog.items(in: category)` and `store.backlog.completedItems`. Change to active project scoped versions.

### AddItemSheet

Category picker currently reads `store.backlog.categories`. Change to active project's categories.

### AddCategorySheet

Currently calls `store.addCategory(name)`. Change to add category to the active project.

## BacklogStore Changes

All mutation methods become project-scoped. They operate on the active project by default, with an optional project parameter.

### New Methods

- `addProject(name: String)` — creates a new project with default "Uncategorized" category
- `deleteProject(id: UUID)` — removes project. If it's the active project, switch to the first remaining project. Items are deleted with the project.
- `renameProject(id: UUID, name: String)` — renames a project
- `switchProject(id: UUID)` — sets `activeProjectId`
- `reorderProjects(_ orderedIds: [UUID])` — reorders the projects array

### Modified Methods

All existing methods operate on the active project. Internal helper:

```swift
private func activeProjectIndex() -> Int? {
    backlog.activeProjectIndex()
}
```

Then each method (addItem, updateItem, completeItem, deleteItem, moveItem, addCategory, deleteCategory, reorderCategories) indexes into `backlog.projects[idx]` instead of `backlog` directly.

## Agent Tool Changes

### Modified Tools (add optional `project` parameter)

All default to the active project when `project` is omitted.

- **`add_item`** — adds `project` (string, optional): project name to add item to
- **`update_item`** — adds `project` (string, optional): move item to a different project
- **`add_category`** — adds `project` (string, optional): project to add category to
- **`reorder_items`** — adds `project` (string, optional): project context
- **`reorder_categories`** — adds `project` (string, optional): project context

### New Tools

- **`add_project(name)`** — creates a new project
- **`delete_project(name)`** — deletes a project and all its items
- **`rename_project(old_name, new_name)`** — renames a project
- **`switch_project(name)`** — sets the active project (updates UI)
- **`reorder_projects(project_names)`** — reorders projects in the switcher

### `read_backlog`

Returns all projects with their items and categories, plus the active project name. The agent has full visibility across all projects.

### System Prompt Update

Add to the agent's system prompt:
- Projects contain categories, which contain items
- Default all operations to the active project unless the user specifies another
- Use `switch_project` when the user wants to work in a different project
- Use `read_backlog` to see all projects and their contents

## Agent Tool Resolution: Project by Name

Agent tools accept project names (strings), not UUIDs. Internally, `AgentService` resolves the name to a project index. If the name doesn't match, return an error. This keeps the agent interface simple — the LLM works with human-readable names.

## Edge Cases

- **Last project deleted**: Prevent deletion if only one project remains. Return an error.
- **Duplicate project names**: Prevent. Return an error from `add_project`.
- **Item moved between projects**: `update_item` with a `project` param moves the item to that project. The item's category must exist in the target project (create it if not).
- **Empty project**: Valid. Shows the "Nothing planted" empty state.
