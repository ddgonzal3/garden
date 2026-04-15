import { startTransition, useEffect, useRef, useState } from "react";
import type { DragEvent, FormEvent, KeyboardEvent } from "react";
import {
  categoryColor,
  createProject,
  getActiveItems,
  getActiveProject,
  getCompletedItems,
  getItemsInBucket,
  getItemsInCategory,
} from "./lib/backlog";
import {
  loadBacklog as loadFromDisk,
  saveProject,
  saveActiveProjectId,
} from "./lib/storage";
import type { Backlog, GardenItem, GardenProject, SidebarSelection } from "./types";

type EditingState = {
  id: string;
  draft: string;
};

function App() {
  const [backlog, setBacklog] = useState<Backlog>({ projects: [], activeProjectId: null });
  const [loaded, setLoaded] = useState(false);
  const [selection, setSelection] = useState<SidebarSelection>({ type: "priorityBoard" });
  const [editing, setEditing] = useState<EditingState | null>(null);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [dropBucket, setDropBucket] = useState<number | null>(null);
  const [dropItemId, setDropItemId] = useState<string | null>(null);

  // Load from disk on mount
  useEffect(() => {
    loadFromDisk()
      .then((data) => {
        setBacklog(data);
        setLoaded(true);
      })
      .catch((err) => {
        console.error("Failed to load backlog from disk:", err);
        setLoaded(true);
      });
  }, []);

  // Persist active project to disk whenever it changes
  const prevBacklogRef = useRef(backlog);
  useEffect(() => {
    if (!loaded) return;
    const prev = prevBacklogRef.current;
    prevBacklogRef.current = backlog;

    // Save active project id if it changed
    if (backlog.activeProjectId && backlog.activeProjectId !== prev.activeProjectId) {
      saveActiveProjectId(backlog.activeProjectId).catch((err) =>
        console.error("Failed to save active project ID:", err),
      );
    }

    // Save any project whose data changed
    const currentActive = backlog.projects.find((p) => p.id === backlog.activeProjectId);
    const prevActive = prev.projects.find((p) => p.id === prev.activeProjectId);
    if (currentActive && currentActive !== prevActive) {
      saveProject(currentActive).catch((err) =>
        console.error("Failed to save project:", err),
      );
    }
  }, [backlog, loaded]);

  const hasData = loaded && backlog.projects.length > 0;
  const activeProject = hasData ? getActiveProject(backlog) : null;
  const activeItems = activeProject ? getActiveItems(activeProject) : [];
  const completedItems = activeProject ? getCompletedItems(activeProject) : [];

  function mutateActiveProject(
    updater: (project: GardenProject) => GardenProject,
    nextSelection?: SidebarSelection,
  ) {
    setBacklog((current) => ({
      ...current,
      projects: current.projects.map((project) =>
        project.id === current.activeProjectId ? updater(project) : project,
      ),
    }));

    if (nextSelection) {
      startTransition(() => setSelection(nextSelection));
    }
  }

  function addProject() {
    const name = window.prompt("New project name");
    if (!name?.trim()) {
      return;
    }

    const project = createProject(name.trim());
    saveProject(project);
    saveActiveProjectId(project.id);
    setBacklog((current) => ({
      projects: [...current.projects, project],
      activeProjectId: project.id,
    }));
    startTransition(() => setSelection({ type: "priorityBoard" }));
  }

  function switchProject(projectId: string) {
    setBacklog((current) => ({ ...current, activeProjectId: projectId }));
    startTransition(() => setSelection({ type: "priorityBoard" }));
    setEditing(null);
  }

  function addCategory() {
    const name = window.prompt("New category name");
    if (!name?.trim()) {
      return;
    }

    mutateActiveProject((project) => {
      if (project.categories.includes(name.trim())) {
        return project;
      }
      return { ...project, categories: [...project.categories, name.trim()] };
    });
  }

  function createNewItem(bucket: number, category = "Uncategorized") {
    const id = crypto.randomUUID();
    mutateActiveProject(
      (project) => {
        const nextPriority =
          project.items
            .filter((item) => item.priorityBucket === bucket && item.completedAt === null)
            .reduce((max, item) => Math.max(max, item.priority), -1) + 1;

        const categories = project.categories.includes(category)
          ? project.categories
          : [...project.categories, category];

        const item: GardenItem = {
          id,
          title: "",
          notes: "",
          category,
          priorityBucket: bucket,
          priority: nextPriority,
          createdAt: new Date().toISOString(),
          completedAt: null,
        };

        return {
          ...project,
          categories,
          items: [...project.items, item],
        };
      },
      category === "Uncategorized" ? { type: "priorityBoard" } : { type: "category", category },
    );

    setEditing({ id, draft: "" });
  }

  function updateItem(itemId: string, updater: (item: GardenItem) => GardenItem) {
    mutateActiveProject((project) => ({
      ...project,
      items: project.items.map((item) => (item.id === itemId ? updater(item) : item)),
    }));
  }

  function deleteItem(itemId: string) {
    mutateActiveProject((project) => ({
      ...project,
      items: project.items.filter((item) => item.id !== itemId),
    }));

    setEditing((current) => (current?.id === itemId ? null : current));
  }

  function completeItem(itemId: string) {
    updateItem(itemId, (item) => ({ ...item, completedAt: new Date().toISOString() }));
  }

  function moveItemToBucket(itemId: string, targetBucket: number) {
    mutateActiveProject((project) => {
      const nextPriority =
        project.items
          .filter(
            (item) =>
              item.priorityBucket === targetBucket &&
              item.completedAt === null &&
              item.id !== itemId,
          )
          .reduce((max, item) => Math.max(max, item.priority), -1) + 1;

      return {
        ...project,
        items: project.items.map((item) =>
          item.id === itemId
            ? { ...item, priorityBucket: targetBucket, priority: nextPriority }
            : item,
        ),
      };
    });
  }

  function moveItemBefore(draggedId: string, targetId: string) {
    mutateActiveProject((project) => {
      const sourceItem = project.items.find((item) => item.id === draggedId);
      const targetItem = project.items.find((item) => item.id === targetId);
      if (!sourceItem || !targetItem) {
        return project;
      }

      const remaining = project.items.filter((item) => item.id !== draggedId);
      const targetIndex = remaining.findIndex((item) => item.id === targetId);
      const insertedItem: GardenItem = {
        ...sourceItem,
        priorityBucket: targetItem.priorityBucket,
      };

      remaining.splice(targetIndex, 0, insertedItem);

      const activeByBucket = new Map<number, number>();
      for (let index = 0; index < remaining.length; index += 1) {
        if (remaining[index].completedAt !== null) {
          continue;
        }

        const bucket = remaining[index].priorityBucket;
        const nextPriority = activeByBucket.get(bucket) ?? 0;
        remaining[index] = { ...remaining[index], priority: nextPriority };
        activeByBucket.set(bucket, nextPriority + 1);
      }

      return { ...project, items: remaining };
    });
  }

  function commitEdit(itemId: string) {
    const current = editing;
    if (!current || current.id !== itemId) {
      return;
    }

    const trimmed = current.draft.trim();
    if (!trimmed) {
      deleteItem(itemId);
      return;
    }

    updateItem(itemId, (item) => ({ ...item, title: trimmed }));
    setEditing(null);
  }

  function visibleItems(): GardenItem[] {
    if (!activeProject) return [];
    switch (selection.type) {
      case "all":
        return activeItems;
      case "completed":
        return completedItems;
      case "category":
        return getItemsInCategory(activeProject, selection.category);
      case "priorityBoard":
        return activeItems;
    }
  }

  const pageTitle =
    selection.type === "priorityBoard"
      ? "Priority"
      : selection.type === "all"
        ? "All"
        : selection.type === "completed"
          ? "Completed"
          : selection.category;

  if (!loaded || !activeProject) {
    return <div className="app-shell"><div className="titlebar" data-tauri-drag-region /></div>;
  }

  return (
    <div className="app-shell">
      <div className="titlebar" data-tauri-drag-region />
      <aside className="sidebar">
        <div className="sidebar-project">
          <select
            className="project-select"
            value={activeProject.id}
            onChange={(event) => switchProject(event.target.value)}
          >
            {backlog.projects.map((project) => (
              <option key={project.id} value={project.id}>
                {project.name}
              </option>
            ))}
          </select>
          <button className="ghost-icon" type="button" onClick={addProject}>
            +
          </button>
        </div>

        <nav className="sidebar-nav">
          <button
            className={selection.type === "all" ? "sidebar-link active" : "sidebar-link"}
            type="button"
            onClick={() => startTransition(() => setSelection({ type: "all" }))}
          >
            <span>All</span>
            <span>{activeItems.length}</span>
          </button>
          <button
            className={
              selection.type === "priorityBoard" ? "sidebar-link active" : "sidebar-link"
            }
            type="button"
            onClick={() => startTransition(() => setSelection({ type: "priorityBoard" }))}
          >
            <span>Priority Board</span>
            <span>{activeItems.length}</span>
          </button>

          <div className="sidebar-section">
            <div className="sidebar-section-head">
              <span>Categories</span>
              <button className="ghost-icon" type="button" onClick={addCategory}>
                +
              </button>
            </div>

            {activeProject.categories.map((category) => (
              <button
                key={category}
                className={
                  selection.type === "category" && selection.category === category
                    ? "sidebar-link active"
                    : "sidebar-link"
                }
                type="button"
                onClick={() => startTransition(() => setSelection({ type: "category", category }))}
              >
                <span>{category}</span>
                <span>{getItemsInCategory(activeProject, category).length}</span>
              </button>
            ))}
          </div>

          <button
            className={selection.type === "completed" ? "sidebar-link active" : "sidebar-link"}
            type="button"
            onClick={() => startTransition(() => setSelection({ type: "completed" }))}
          >
            <span>Completed</span>
            <span>{completedItems.length}</span>
          </button>
        </nav>
      </aside>

      <main className="workspace">
        <header className="workspace-header">
          <div>
            <div className="eyebrow">{activeProject.name}</div>
            <h1>{pageTitle}</h1>
          </div>
          <div className="workspace-actions">
            <button className="toolbar-button" type="button" onClick={addCategory}>
              New Category
            </button>
            <button className="toolbar-button primary" type="button" onClick={() => createNewItem(0)}>
              New Item
            </button>
          </div>
        </header>

        {selection.type === "priorityBoard" ? (
          <section className="board-shell">
            <div className="board">
              {Array.from({ length: activeProject.priorityBucketCount }, (_, bucket) => (
                <div
                  key={bucket}
                  className={dropBucket === bucket ? "column drop-active" : "column"}
                  onDragOver={(event) => {
                    event.preventDefault();
                    setDropBucket(bucket);
                    setDropItemId(null);
                  }}
                  onDragLeave={() => setDropBucket((current) => (current === bucket ? null : current))}
                  onDrop={() => {
                    if (draggingId) {
                      moveItemToBucket(draggingId, bucket);
                    }
                    setDropBucket(null);
                    setDraggingId(null);
                  }}
                >
                  <div className="column-head">
                    <div className="column-title">P{bucket + 1}</div>
                    <button className="count-pill" type="button" onClick={() => createNewItem(bucket)}>
                      {getItemsInBucket(activeProject, bucket).length}
                    </button>
                  </div>
                  <div className="column-rule" />
                  <div className="stack">
                    {getItemsInBucket(activeProject, bucket).map((item) => (
                      <TaskCard
                        key={item.id}
                        item={item}
                        editing={editing}
                        maxBucket={activeProject.priorityBucketCount - 1}
                        onEditChange={setEditing}
                        onCommitEdit={commitEdit}
                        onDelete={deleteItem}
                        onComplete={completeItem}
                        onMoveBucket={moveItemToBucket}
                        isDropTarget={dropItemId === item.id}
                        onDragStart={(event) => {
                          event.dataTransfer.effectAllowed = "move";
                          setDraggingId(item.id);
                        }}
                        onDragEnd={() => {
                          setDraggingId(null);
                          setDropBucket(null);
                          setDropItemId(null);
                        }}
                        onDragOver={(event) => {
                          event.preventDefault();
                          setDropItemId(item.id);
                          setDropBucket(null);
                        }}
                        onDrop={(event) => {
                          event.preventDefault();
                          if (draggingId && draggingId !== item.id) {
                            moveItemBefore(draggingId, item.id);
                          }
                          setDropItemId(null);
                          setDraggingId(null);
                        }}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </section>
        ) : (
          <section className="list-shell">
            <div className="list-grid">
              {visibleItems().map((item) => (
                <TaskCard
                  key={item.id}
                  item={item}
                  editing={editing}
                  maxBucket={activeProject.priorityBucketCount - 1}
                  onEditChange={setEditing}
                  onCommitEdit={commitEdit}
                  onDelete={deleteItem}
                  onComplete={completeItem}
                  onMoveBucket={moveItemToBucket}
                />
              ))}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}

type TaskCardProps = {
  item: GardenItem;
  editing: EditingState | null;
  maxBucket: number;
  onEditChange: (editing: EditingState | null) => void;
  onCommitEdit: (itemId: string) => void;
  onDelete: (itemId: string) => void;
  onComplete: (itemId: string) => void;
  onMoveBucket: (itemId: string, bucket: number) => void;
  isDropTarget?: boolean;
  onDragStart?: (event: DragEvent<HTMLElement>) => void;
  onDragEnd?: () => void;
  onDragOver?: (event: DragEvent<HTMLElement>) => void;
  onDrop?: (event: DragEvent<HTMLElement>) => void;
};

function TaskCard({
  item,
  editing,
  maxBucket,
  onEditChange,
  onCommitEdit,
  onDelete,
  onComplete,
  onMoveBucket,
  isDropTarget = false,
  onDragStart,
  onDragEnd,
  onDragOver,
  onDrop,
}: TaskCardProps) {
  const color = categoryColor(item.category);
  const isEditing = editing?.id === item.id;

  function submitEdit(event: FormEvent) {
    event.preventDefault();
    onCommitEdit(item.id);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Escape") {
      onCommitEdit(item.id);
    }
  }

  return (
    <article
      className={isDropTarget ? "task-card drop-target" : "task-card"}
      style={{ ["--card-accent" as string]: color }}
      draggable
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      onDragOver={onDragOver}
      onDrop={onDrop}
      onDoubleClick={() => onEditChange({ id: item.id, draft: item.title })}
    >
      <div className="task-card-actions">
        <button className="ghost-icon" type="button" onClick={() => onMoveBucket(item.id, Math.max(0, item.priorityBucket - 1))}>
          ←
        </button>
        <button className="ghost-icon" type="button" onClick={() => onMoveBucket(item.id, Math.min(maxBucket, item.priorityBucket + 1))}>
          →
        </button>
        <button className="ghost-icon" type="button" onClick={() => onComplete(item.id)}>
          ✓
        </button>
        <button className="ghost-icon" type="button" onClick={() => onDelete(item.id)}>
          ×
        </button>
      </div>

      {isEditing ? (
        <form onSubmit={submitEdit}>
          <input
            autoFocus
            className="task-input"
            value={editing.draft}
            onChange={(event) => onEditChange({ id: item.id, draft: event.target.value })}
            onBlur={() => onCommitEdit(item.id)}
            onKeyDown={handleKeyDown}
            placeholder="New item..."
          />
        </form>
      ) : (
        <h2 className="task-title">{item.title || "Untitled task"}</h2>
      )}

      <div className="task-meta">
        {item.category}
      </div>
    </article>
  );
}

export default App;
