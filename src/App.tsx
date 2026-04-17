import { startTransition, useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import {
  DndContext,
  DragOverlay,
  pointerWithin,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import type { DragStartEvent, DragOverEvent, DragEndEvent } from "@dnd-kit/core";
import {
  arrayMove,
  SortableContext,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useDroppable } from "@dnd-kit/core";
import {
  bucketLabel,
  categoryColor,
  colorPalette,
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
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [activeDragId, setActiveDragId] = useState<string | null>(null);
  const [categoryPickerItemId, setCategoryPickerItemId] = useState<string | null>(null);
  const [sidebarHidden, setSidebarHidden] = useState<boolean>(
    () => localStorage.getItem("garden-sidebar-hidden") === "1",
  );
  const [addingCategory, setAddingCategory] = useState(false);
  const [categoryDraft, setCategoryDraft] = useState("");
  const [renamingCategory, setRenamingCategory] = useState<string | null>(null);
  const [sidebarColorCategory, setSidebarColorCategory] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [notesItemId, setNotesItemId] = useState<string | null>(null);
  const [addingProject, setAddingProject] = useState(false);
  const [projectDraft, setProjectDraft] = useState("");
  const undoStackRef = useRef<GardenProject[]>([]);
  const dragStartBucketRef = useRef<number | null>(null);

  const toggleSidebar = useCallback(() => {
    setSidebarHidden((prev) => {
      const next = !prev;
      localStorage.setItem("garden-sidebar-hidden", next ? "1" : "0");
      return next;
    });
  }, []);

  // dnd-kit sensor: require 5px of movement before starting a drag
  // so clicks/double-clicks don't accidentally trigger drags
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
  );

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

    if (backlog.activeProjectId && backlog.activeProjectId !== prev.activeProjectId) {
      saveActiveProjectId(backlog.activeProjectId).catch((err) =>
        console.error("Failed to save active project ID:", err),
      );
    }

    const currentActive = backlog.projects.find((p) => p.id === backlog.activeProjectId);
    const prevActive = prev.projects.find((p) => p.id === prev.activeProjectId);
    if (currentActive && currentActive !== prevActive) {
      saveProject(currentActive).catch((err) =>
        console.error("Failed to save project:", err),
      );
    }
  }, [backlog, loaded]);

  // Restore persisted zoom on mount
  useEffect(() => {
    const saved = Number.parseFloat(localStorage.getItem("garden-zoom") ?? "");
    if (Number.isFinite(saved) && saved > 0) {
      (document.body.style as unknown as Record<string, string>).zoom = String(saved);
    }
  }, []);

  // Global keyboard handler for delete + undo + zoom
  useEffect(() => {
    function handleKeyDown(event: globalThis.KeyboardEvent) {
      // Cmd+Z / Ctrl+Z to undo (works even while editing)
      if ((event.metaKey || event.ctrlKey) && event.key === "z") {
        event.preventDefault();
        undo();
        return;
      }

      // Cmd+B / Ctrl+B to toggle sidebar
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "b") {
        event.preventDefault();
        toggleSidebar();
        return;
      }

      // Cmd+=/Cmd+-/Cmd+0 to zoom the webview
      if (event.metaKey || event.ctrlKey) {
        const isZoomIn = event.key === "=" || event.key === "+";
        const isZoomOut = event.key === "-" || event.key === "_";
        const isZoomReset = event.key === "0";
        if (isZoomIn || isZoomOut || isZoomReset) {
          event.preventDefault();
          const style = document.body.style as unknown as Record<string, string>;
          const current = Number.parseFloat(style.zoom || "1") || 1;
          const next = isZoomReset
            ? 1
            : isZoomIn
              ? Math.min(3, Math.round((current + 0.1) * 100) / 100)
              : Math.max(0.5, Math.round((current - 0.1) * 100) / 100);
          style.zoom = String(next);
          localStorage.setItem("garden-zoom", String(next));
          return;
        }
      }

      if (editing) return; // don't delete while editing
      if (!selectedId) return;
      if (event.key === "Backspace" || event.key === "Delete") {
        event.preventDefault();
        deleteItem(selectedId);
        setSelectedId(null);
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedId, editing]);

  const hasData = loaded && backlog.projects.length > 0;
  const activeProject = hasData ? getActiveProject(backlog) : null;
  const activeItems = activeProject ? getActiveItems(activeProject) : [];
  const completedItems = activeProject ? getCompletedItems(activeProject) : [];

  function mutateActiveProject(
    updater: (project: GardenProject) => GardenProject,
    nextSelection?: SidebarSelection,
  ) {
    setBacklog((current) => {
      // Push current project snapshot onto undo stack before mutating
      const currentProject = current.projects.find((p) => p.id === current.activeProjectId);
      if (currentProject) {
        undoStackRef.current = [...undoStackRef.current.slice(-49), currentProject];
      }

      return {
        ...current,
        projects: current.projects.map((project) =>
          project.id === current.activeProjectId ? updater(project) : project,
        ),
      };
    });

    if (nextSelection) {
      startTransition(() => setSelection(nextSelection));
    }
  }

  function undo() {
    const stack = undoStackRef.current;
    if (stack.length === 0) return;

    const previous = stack[stack.length - 1];
    undoStackRef.current = stack.slice(0, -1);

    setBacklog((current) => ({
      ...current,
      projects: current.projects.map((project) =>
        project.id === previous.id ? previous : project,
      ),
    }));
    setEditing(null);
    setSelectedId(null);
  }

  function commitNewProject() {
    const trimmed = projectDraft.trim();
    setAddingProject(false);
    setProjectDraft("");
    if (!trimmed) return;

    const project = createProject(trimmed);
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
    setSelectedId(null);
  }

  function commitNewCategory() {
    const trimmed = categoryDraft.trim();
    setAddingCategory(false);
    setCategoryDraft("");
    if (!trimmed) return;

    mutateActiveProject((project) => {
      if (project.categories.includes(trimmed)) return project;
      return { ...project, categories: [...project.categories, trimmed] };
    });
  }

  function createNewItem(
    bucket: number,
    category = "Uncategorized",
    position: "top" | "bottom" = "top",
  ) {
    const id = crypto.randomUUID();
    mutateActiveProject(
      (project) => {
        const categories = project.categories.includes(category)
          ? project.categories
          : [...project.categories, category];

        let items = project.items;
        let priority: number;

        if (position === "top") {
          // Shift existing bucket items down, new item takes priority 0.
          items = items.map((item) =>
            item.priorityBucket === bucket && item.completedAt === null
              ? { ...item, priority: item.priority + 1 }
              : item,
          );
          priority = 0;
        } else {
          // Append at end — priority = max + 1.
          priority =
            project.items
              .filter((i) => i.priorityBucket === bucket && i.completedAt === null)
              .reduce((max, i) => Math.max(max, i.priority), -1) + 1;
        }

        const item: GardenItem = {
          id,
          title: "",
          notes: "",
          category,
          priorityBucket: bucket,
          priority,
          createdAt: new Date().toISOString(),
          completedAt: null,
          status: "idle",
        };

        return { ...project, categories, items: [...items, item] };
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

  function completeItem(itemId: string) {
    updateItem(itemId, (item) => ({ ...item, completedAt: new Date().toISOString() }));
    setSelectedId(null);
  }

  function toggleInProgress(itemId: string) {
    updateItem(itemId, (item) => ({
      ...item,
      status: item.status === "inProgress" ? "idle" : "inProgress",
    }));
  }

  function setItemNotes(itemId: string, notes: string) {
    updateItem(itemId, (item) => ({ ...item, notes }));
  }

  function deleteItem(itemId: string) {
    mutateActiveProject((project) => ({
      ...project,
      items: project.items.filter((item) => item.id !== itemId),
    }));
    setEditing((current) => (current?.id === itemId ? null : current));
  }

  function renameCategory(oldName: string, newName: string) {
    const trimmed = newName.trim();
    if (!trimmed || trimmed === oldName) return;

    mutateActiveProject((project) => {
      // If target name already exists, merge (items + keep existing color)
      const merging = project.categories.includes(trimmed);
      const categories = merging
        ? project.categories.filter((c) => c !== oldName)
        : project.categories.map((c) => (c === oldName ? trimmed : c));

      const categoryColors = { ...project.categoryColors };
      if (!merging && categoryColors[oldName]) {
        categoryColors[trimmed] = categoryColors[oldName];
      }
      delete categoryColors[oldName];

      return {
        ...project,
        categories,
        categoryColors,
        items: project.items.map((item) =>
          item.category === oldName ? { ...item, category: trimmed } : item,
        ),
      };
    });

    setSelection((current) =>
      current.type === "category" && current.category === oldName
        ? { type: "category", category: trimmed }
        : current,
    );
  }

  function changeCategory(itemId: string, category: string) {
    mutateActiveProject((project) => {
      const categories = project.categories.includes(category)
        ? project.categories
        : [...project.categories, category];
      return {
        ...project,
        categories,
        items: project.items.map((item) =>
          item.id === itemId ? { ...item, category } : item,
        ),
      };
    });
    setCategoryPickerItemId(null);
  }

  function renameBucket(bucket: number, name: string) {
    const trimmed = name.trim();
    if (!trimmed) return;
    mutateActiveProject((project) => {
      const next = [...project.bucketNames];
      next[bucket] = trimmed;
      return { ...project, bucketNames: next };
    });
  }

  function setCategoryColor(category: string, color: string) {
    mutateActiveProject((project) => ({
      ...project,
      categoryColors: { ...project.categoryColors, [category]: color },
    }));
  }

  function rememberCustomColor(color: string) {
    mutateActiveProject((project) => {
      const normalized = color.toLowerCase();
      const isPreset = colorPalette.some((c) => c.toLowerCase() === normalized);
      const hasCustom = project.customColors.some((c) => c.toLowerCase() === normalized);
      if (isPreset || hasCustom) return project;
      return {
        ...project,
        customColors: [color, ...project.customColors].slice(0, 24),
      };
    });
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
      if (!sourceItem || !targetItem) return project;

      const remaining = project.items.filter((item) => item.id !== draggedId);
      const targetIndex = remaining.findIndex((item) => item.id === targetId);
      const insertedItem: GardenItem = {
        ...sourceItem,
        priorityBucket: targetItem.priorityBucket,
      };

      remaining.splice(targetIndex, 0, insertedItem);

      const activeByBucket = new Map<number, number>();
      for (let index = 0; index < remaining.length; index += 1) {
        if (remaining[index].completedAt !== null) continue;
        const bucket = remaining[index].priorityBucket;
        const nextPriority = activeByBucket.get(bucket) ?? 0;
        remaining[index] = { ...remaining[index], priority: nextPriority };
        activeByBucket.set(bucket, nextPriority + 1);
      }

      return { ...project, items: remaining };
    });
  }

  function reorderWithinBucket(draggedId: string, overId: string) {
    mutateActiveProject((project) => {
      const dragged = project.items.find((i) => i.id === draggedId);
      const over = project.items.find((i) => i.id === overId);
      if (!dragged || !over || dragged.priorityBucket !== over.priorityBucket) return project;

      const bucket = dragged.priorityBucket;
      const bucketItems = project.items
        .filter((i) => i.priorityBucket === bucket && i.completedAt === null)
        .sort((a, b) => a.priority - b.priority);

      const oldIndex = bucketItems.findIndex((i) => i.id === draggedId);
      const newIndex = bucketItems.findIndex((i) => i.id === overId);
      if (oldIndex === -1 || newIndex === -1 || oldIndex === newIndex) return project;

      const reordered = arrayMove(bucketItems, oldIndex, newIndex);
      const priorityMap = new Map<string, number>();
      reordered.forEach((item, idx) => priorityMap.set(item.id, idx));

      return {
        ...project,
        items: project.items.map((item) =>
          priorityMap.has(item.id)
            ? { ...item, priority: priorityMap.get(item.id)! }
            : item,
        ),
      };
    });
  }

  function moveItemAfterLast(draggedId: string, targetBucket: number) {
    mutateActiveProject((project) => {
      const sourceItem = project.items.find((item) => item.id === draggedId);
      if (!sourceItem) return project;

      const remaining = project.items.filter((item) => item.id !== draggedId);
      const insertedItem: GardenItem = { ...sourceItem, priorityBucket: targetBucket };
      remaining.push(insertedItem);

      const activeByBucket = new Map<number, number>();
      for (let index = 0; index < remaining.length; index += 1) {
        if (remaining[index].completedAt !== null) continue;
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
    if (!current || current.id !== itemId) return;

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

  // --- dnd-kit handlers ---

  const handleDragStart = useCallback((event: DragStartEvent) => {
    const activeId = String(event.active.id);
    setActiveDragId(activeId);
    const item = activeProject?.items.find((i) => i.id === activeId);
    dragStartBucketRef.current = item?.priorityBucket ?? null;
  }, [activeProject]);

  const handleDragOver = useCallback((event: DragOverEvent) => {
    const { active, over } = event;
    if (!over || !activeProject) return;

    const activeId = String(active.id);
    const overId = String(over.id);
    const activeItem = activeProject.items.find((item) => item.id === activeId);
    if (!activeItem) return;

    // Determine target bucket from the over element.
    let targetBucket: number;
    if (overId.startsWith("column-")) {
      targetBucket = Number.parseInt(overId.split("-")[1], 10);
    } else {
      const overItem = activeProject.items.find((item) => item.id === overId);
      if (!overItem) return;
      targetBucket = overItem.priorityBucket;
    }

    // Same bucket → don't mutate during drag; onDragEnd commits final order.
    if (targetBucket === activeItem.priorityBucket) return;

    // Cross-bucket: move into target bucket near the hovered card (or append).
    if (overId.startsWith("column-")) {
      moveItemToBucket(activeId, targetBucket);
    } else {
      moveItemBefore(activeId, overId);
    }
  }, [activeProject]);

  const handleDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event;
    setActiveDragId(null);
    const startBucket = dragStartBucketRef.current;
    dragStartBucketRef.current = null;

    if (!over || !activeProject) return;

    const activeId = String(active.id);
    const overId = String(over.id);
    if (activeId === overId) return;

    const activeItem = activeProject.items.find((item) => item.id === activeId);
    if (!activeItem) return;

    // Dropped on an empty column — send to end of that bucket.
    if (overId.startsWith("column-")) {
      const bucket = Number.parseInt(overId.split("-")[1], 10);
      moveItemAfterLast(activeId, bucket);
      return;
    }

    const overItem = activeProject.items.find((item) => item.id === overId);
    if (!overItem) return;

    // Same-bucket drag (never left origin bucket) → arrayMove reorder.
    if (startBucket === overItem.priorityBucket && activeItem.priorityBucket === overItem.priorityBucket) {
      reorderWithinBucket(activeId, overId);
      return;
    }

    // Cross-bucket drop: onDragOver already positioned active.
    // No-op here (current state is final).
  }, [activeProject]);

  // Find the actively dragged item for the overlay
  const activeDragItem = activeProject?.items.find((item) => item.id === activeDragId) ?? null;

  // Click on empty space deselects and closes pickers
  const handleBackgroundClick = useCallback(() => {
    setSelectedId(null);
    setCategoryPickerItemId(null);
  }, []);

  if (!loaded || !activeProject) {
    return <div className="app-shell"><div className="titlebar" data-tauri-drag-region /></div>;
  }

  return (
    <div className={sidebarHidden ? "app-shell sidebar-hidden" : "app-shell"} onClick={handleBackgroundClick}>
      <div className="titlebar" data-tauri-drag-region>
        <button
          className={sidebarHidden ? "sidebar-toggle closed" : "sidebar-toggle"}
          type="button"
          onClick={(e) => { e.stopPropagation(); toggleSidebar(); }}
          aria-label={sidebarHidden ? "Show sidebar" : "Hide sidebar"}
          title={sidebarHidden ? "Show sidebar (⌘B)" : "Hide sidebar (⌘B)"}
        >
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor" strokeWidth="1.5">
            <rect x="3" y="4.5" width="16" height="13" rx="2.6" />
            <line x1="8.5" y1="4.5" x2="8.5" y2="17.5" />
            <rect className="sidebar-toggle-fill" x="3" y="4.5" width="5.5" height="13" rx="2.6" fill="currentColor" stroke="none" />
          </svg>
        </button>
        <div className="titlebar-project-name" data-tauri-drag-region>
          <svg className="titlebar-leaf" width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M9 16 V 9.5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            <path d="M9 10.5 C 6 9.5, 3 7.5, 1.5 4 C 4 4.5, 7.5 5.5, 9 9 Z" fill="currentColor" opacity="0.85" />
            <path d="M9 9.5 C 11 6, 13.5 3, 16.5 2 C 17 6, 14 10, 9 10.5 Z" fill="currentColor" />
          </svg>
          <span>{activeProject.name}</span>
        </div>
      </div>
      <aside className="sidebar" onClick={(e) => e.stopPropagation()}>
        <ProjectSelect
          projects={backlog.projects}
          activeId={activeProject.id}
          isActive={selection.type === "priorityBoard"}
          onSelect={switchProject}
          onNavigate={() => startTransition(() => setSelection({ type: "priorityBoard" }))}
          onRequestNewProject={() => { setAddingProject(true); setProjectDraft(""); }}
        />
        {addingProject && (
          <input
            autoFocus
            className="inline-add-input"
            value={projectDraft}
            placeholder="Project name"
            onChange={(e) => setProjectDraft(e.target.value)}
            onBlur={commitNewProject}
            onKeyDown={(e) => {
              if (e.key === "Enter") commitNewProject();
              else if (e.key === "Escape") { setAddingProject(false); setProjectDraft(""); }
            }}
          />
        )}

        <nav className="sidebar-nav">
          <div className="sidebar-section">
            <div className="sidebar-section-head">
              <span>Categories</span>
              <button
                className="ghost-icon"
                type="button"
                onClick={() => { setAddingCategory(true); setCategoryDraft(""); }}
              >
                +
              </button>
            </div>

            {addingCategory && (
              <input
                autoFocus
                className="inline-add-input"
                value={categoryDraft}
                placeholder="Category name"
                onChange={(e) => setCategoryDraft(e.target.value)}
                onBlur={commitNewCategory}
                onKeyDown={(e) => {
                  if (e.key === "Enter") commitNewCategory();
                  else if (e.key === "Escape") { setAddingCategory(false); setCategoryDraft(""); }
                }}
              />
            )}

            {activeProject.categories.map((category) => {
              const isRenaming = renamingCategory === category;
              const commitRename = () => {
                const trimmed = renameDraft.trim();
                setRenamingCategory(null);
                setRenameDraft("");
                if (trimmed && trimmed !== category) renameCategory(category, trimmed);
              };

              if (isRenaming) {
                return (
                  <input
                    key={category}
                    autoFocus
                    className="inline-add-input"
                    value={renameDraft}
                    onChange={(e) => setRenameDraft(e.target.value)}
                    onBlur={commitRename}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") commitRename();
                      else if (e.key === "Escape") { setRenamingCategory(null); setRenameDraft(""); }
                    }}
                  />
                );
              }

              return (
                <SidebarCategoryRow
                  key={category}
                  category={category}
                  color={categoryColor(category, activeProject.categoryColors)}
                  customColors={activeProject.customColors}
                  count={getItemsInCategory(activeProject, category).length}
                  isActive={selection.type === "category" && selection.category === category}
                  isColorPickerOpen={sidebarColorCategory === category}
                  onSelect={() => startTransition(() => setSelection({ type: "category", category }))}
                  onStartRename={() => { setRenamingCategory(category); setRenameDraft(category); }}
                  onToggleColorPicker={() =>
                    setSidebarColorCategory((cur) => (cur === category ? null : category))
                  }
                  onCloseColorPicker={() => setSidebarColorCategory(null)}
                  onPickColor={(c) => setCategoryColor(category, c)}
          onCommitCustomColor={(c) => rememberCustomColor(c)}
                />
              );
            })}
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

      <main className="workspace" onClick={(e) => e.stopPropagation()}>
        <DndContext
          sensors={sensors}
          collisionDetection={pointerWithin}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
        >
          {selection.type === "priorityBoard" ? (
            <section className="board-shell">
              <div className="board">
                {Array.from({ length: activeProject.priorityBucketCount }, (_, bucket) => {
                  const bucketItems = getItemsInBucket(activeProject, bucket);
                  return (
                    <DroppableColumn
                      key={bucket}
                      bucket={bucket}
                      label={bucketLabel(activeProject, bucket)}
                      onAddItem={createNewItem}
                      onRename={renameBucket}
                    >
                      <SortableContext
                        items={bucketItems.map((item) => item.id)}
                        strategy={verticalListSortingStrategy}
                      >
                        <div
                          className="stack"
                          onDoubleClick={(e) => {
                            // Only fire when double-clicking empty stack area, not a card
                            if (e.target === e.currentTarget) {
                              createNewItem(bucket, "Uncategorized", "bottom");
                            }
                          }}
                        >
                          {bucketItems.map((item) => (
                            <SortableTaskCard
                              key={item.id}
                              item={item}
                              editing={editing}
                              categories={activeProject.categories}
                              categoryColors={activeProject.categoryColors}
                              customColors={activeProject.customColors}
                              categoryPickerItemId={categoryPickerItemId}
                              isSelected={selectedId === item.id}
                              isDragOverlay={false}
                              isBeingDragged={activeDragId === item.id}
                              onSelect={(id) => setSelectedId(id)}
                              onEditChange={setEditing}
                              onCommitEdit={commitEdit}
                              onComplete={completeItem}
                              onCategoryClick={(id) => setCategoryPickerItemId((cur) => cur === id ? null : id)}
                              onChangeCategory={changeCategory}
                              onSetCategoryColor={setCategoryColor}
                              onRememberCustomColor={rememberCustomColor}
                              onRenameCategory={renameCategory}
                              onToggleInProgress={toggleInProgress}
                              onOpenNotes={(id) => setNotesItemId(id)}
                              onCloseCategoryPicker={() => setCategoryPickerItemId(null)}
                            />
                          ))}
                        </div>
                      </SortableContext>
                    </DroppableColumn>
                  );
                })}
              </div>
            </section>
          ) : (
            <section className="list-shell">
              <SortableContext
                items={visibleItems().map((item) => item.id)}
                strategy={verticalListSortingStrategy}
              >
                <div className="list-grid">
                  {visibleItems().map((item) => (
                    <SortableTaskCard
                      key={item.id}
                      item={item}
                      editing={editing}
                      categories={activeProject.categories}
                      categoryColors={activeProject.categoryColors}
                      customColors={activeProject.customColors}
                      categoryPickerItemId={categoryPickerItemId}
                      isSelected={selectedId === item.id}
                      isDragOverlay={false}
                      isBeingDragged={activeDragId === item.id}
                      onSelect={(id) => setSelectedId(id)}
                      onEditChange={setEditing}
                      onCommitEdit={commitEdit}
                      onComplete={completeItem}
                      onCategoryClick={(id) => setCategoryPickerItemId((cur) => cur === id ? null : id)}
                      onChangeCategory={changeCategory}
                      onSetCategoryColor={setCategoryColor}
                      onRememberCustomColor={rememberCustomColor}
                      onRenameCategory={renameCategory}
                      onToggleInProgress={toggleInProgress}
                      onOpenNotes={(id) => setNotesItemId(id)}
                      onCloseCategoryPicker={() => setCategoryPickerItemId(null)}
                    />
                  ))}
                </div>
              </SortableContext>
            </section>
          )}

          <DragOverlay dropAnimation={{ duration: 200, easing: "ease" }}>
            {activeDragItem ? (
              <TaskCardContent
                item={activeDragItem}
                editing={null}
                categoryColors={activeProject.categoryColors}
                customColors={activeProject.customColors}
                isSelected={false}
                isDragOverlay={true}
                isBeingDragged={false}
              />
            ) : null}
          </DragOverlay>
        </DndContext>
      </main>
      {notesItemId && (() => {
        const item = activeProject.items.find((i) => i.id === notesItemId);
        if (!item) return null;
        return (
          <NotesModal
            key={item.id}
            title={item.title || "Untitled task"}
            notes={item.notes}
            onChange={(val) => setItemNotes(item.id, val)}
            onClose={() => setNotesItemId(null)}
          />
        );
      })()}
    </div>
  );
}

// --- Droppable column wrapper ---

function DroppableColumn({
  bucket,
  label,
  onAddItem,
  onRename,
  children,
}: {
  bucket: number;
  label: string;
  onAddItem: (bucket: number) => void;
  onRename: (bucket: number, name: string) => void;
  children: React.ReactNode;
}) {
  const { setNodeRef, isOver } = useDroppable({ id: `column-${bucket}` });
  const [isEditing, setIsEditing] = useState(false);
  const [draft, setDraft] = useState(label);

  function commit() {
    setIsEditing(false);
    const trimmed = draft.trim();
    if (trimmed && trimmed !== label) onRename(bucket, trimmed);
    else setDraft(label);
  }

  return (
    <div
      ref={setNodeRef}
      className={isOver ? "column drop-active" : "column"}
    >
      <div className="column-head">
        {isEditing ? (
          <input
            autoFocus
            className="column-title-input"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={commit}
            onKeyDown={(e) => {
              if (e.key === "Enter") commit();
              else if (e.key === "Escape") { setDraft(label); setIsEditing(false); }
            }}
          />
        ) : (
          <div
            className="column-title"
            onDoubleClick={(e) => { e.stopPropagation(); setDraft(label); setIsEditing(true); }}
          >
            {label}
          </div>
        )}
        <button
          className="column-add-btn"
          type="button"
          onClick={() => onAddItem(bucket)}
          aria-label="Add item"
        >
          +
        </button>
      </div>
      {children}
    </div>
  );
}

// --- Sortable card wrapper ---

type SortableTaskCardProps = {
  item: GardenItem;
  editing: EditingState | null;
  categories: string[];
  categoryColors: Record<string, string>;
  customColors: string[];
  categoryPickerItemId: string | null;
  isSelected: boolean;
  isDragOverlay: boolean;
  isBeingDragged: boolean;
  onSelect: (id: string) => void;
  onEditChange: (editing: EditingState | null) => void;
  onCommitEdit: (itemId: string) => void;
  onComplete: (itemId: string) => void;
  onCategoryClick: (itemId: string) => void;
  onChangeCategory: (itemId: string, category: string) => void;
  onSetCategoryColor: (category: string, color: string) => void;
  onRememberCustomColor: (color: string) => void;
  onRenameCategory: (oldName: string, newName: string) => void;
  onToggleInProgress: (itemId: string) => void;
  onOpenNotes: (itemId: string) => void;
  onCloseCategoryPicker: () => void;
};

function SortableTaskCard({
  item,
  editing,
  categories,
  categoryColors,
  customColors,
  categoryPickerItemId,
  isSelected,
  isDragOverlay,
  isBeingDragged,
  onSelect,
  onEditChange,
  onCommitEdit,
  onComplete,
  onCategoryClick,
  onChangeCategory,
  onSetCategoryColor,
  onRememberCustomColor,
  onRenameCategory,
  onToggleInProgress,
  onOpenNotes,
  onCloseCategoryPicker,
}: SortableTaskCardProps) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: item.id });

  const showPicker = categoryPickerItemId === item.id;
  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    position: "relative",
    zIndex: showPicker ? 50 : undefined,
  };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <TaskCardContent
        item={item}
        editing={editing}
        categories={categories}
        categoryColors={categoryColors}
        customColors={customColors}
        showCategoryPicker={categoryPickerItemId === item.id}
        isSelected={isSelected}
        isDragOverlay={isDragOverlay}
        isBeingDragged={isDragging || isBeingDragged}
        onSelect={onSelect}
        onEditChange={onEditChange}
        onCommitEdit={onCommitEdit}
        onComplete={onComplete}
        onCategoryClick={onCategoryClick}
        onChangeCategory={onChangeCategory}
        onSetCategoryColor={onSetCategoryColor}
        onRememberCustomColor={onRememberCustomColor}
        onRenameCategory={onRenameCategory}
        onToggleInProgress={onToggleInProgress}
        onOpenNotes={onOpenNotes}
        onCloseCategoryPicker={onCloseCategoryPicker}
      />
    </div>
  );
}

// --- Card presentation ---

type TaskCardContentProps = {
  item: GardenItem;
  editing: EditingState | null;
  categories?: string[];
  categoryColors?: Record<string, string>;
  customColors?: string[];
  showCategoryPicker?: boolean;
  isSelected: boolean;
  isDragOverlay: boolean;
  isBeingDragged: boolean;
  onSelect?: (id: string) => void;
  onEditChange?: (editing: EditingState | null) => void;
  onCommitEdit?: (itemId: string) => void;
  onComplete?: (itemId: string) => void;
  onCategoryClick?: (itemId: string) => void;
  onChangeCategory?: (itemId: string, category: string) => void;
  onSetCategoryColor?: (category: string, color: string) => void;
  onRememberCustomColor?: (color: string) => void;
  onRenameCategory?: (oldName: string, newName: string) => void;
  onToggleInProgress?: (itemId: string) => void;
  onOpenNotes?: (itemId: string) => void;
  onCloseCategoryPicker?: () => void;
};

function TaskCardContent({
  item,
  editing,
  categories = [],
  categoryColors = {},
  customColors = [],
  showCategoryPicker = false,
  isSelected,
  isDragOverlay,
  isBeingDragged,
  onSelect,
  onEditChange,
  onCommitEdit,
  onComplete,
  onCategoryClick,
  onChangeCategory,
  onSetCategoryColor,
  onRememberCustomColor,
  onRenameCategory,
  onToggleInProgress,
  onOpenNotes,
  onCloseCategoryPicker,
}: TaskCardContentProps) {
  const color = categoryColor(item.category, categoryColors);
  const [editingColorFor, setEditingColorFor] = useState<string | null>(null);
  const [pickerNewCatDraft, setPickerNewCatDraft] = useState<string | null>(null);
  const [renamingCatInPicker, setRenamingCatInPicker] = useState<string | null>(null);
  const [renameCatDraft, setRenameCatDraft] = useState("");
  const [directColorOpen, setDirectColorOpen] = useState(false);
  const isEditing = editing?.id === item.id;
  const pickerRef = useRef<HTMLDivElement>(null);

  // Click outside closes category picker
  useEffect(() => {
    if (!showCategoryPicker) return;
    function handleOutsideClick(event: MouseEvent) {
      if (pickerRef.current && !pickerRef.current.contains(event.target as Node)) {
        onCloseCategoryPicker?.();
      }
    }
    document.addEventListener("mousedown", handleOutsideClick);
    return () => document.removeEventListener("mousedown", handleOutsideClick);
  }, [showCategoryPicker, onCloseCategoryPicker]);

  const classNames = [
    "task-card",
    isSelected && "selected",
    isDragOverlay && "drag-overlay",
    isBeingDragged && "dragging",
    item.status === "inProgress" && "in-progress",
  ]
    .filter(Boolean)
    .join(" ");

  function handleClick(event: React.MouseEvent) {
    event.stopPropagation();
    if (isEditing) return;
    onSelect?.(item.id);
    onOpenNotes?.(item.id);
  }

  function handleTitleClick(event: React.MouseEvent) {
    event.stopPropagation();
    if (isEditing) return;
    onEditChange?.({ id: item.id, draft: item.title });
  }

  function handleCategoryClick(event: React.MouseEvent) {
    event.stopPropagation();
    onCategoryClick?.(item.id);
  }

  function handlePickCategory(category: string) {
    onChangeCategory?.(item.id, category);
  }

  function commitPickerNewCategory() {
    const trimmed = (pickerNewCatDraft ?? "").trim();
    setPickerNewCatDraft(null);
    if (trimmed) onChangeCategory?.(item.id, trimmed);
  }

  return (
    <article
      className={classNames}
      style={{ ["--card-accent" as string]: color }}
      onClick={handleClick}
    >
      {isEditing ? (
        <TitleEditor
          value={editing.draft}
          onChange={(val) => onEditChange?.({ id: item.id, draft: val })}
          onCommit={() => onCommitEdit?.(item.id)}
        />
      ) : (
        <h2 className="task-title" onClick={handleTitleClick}>{item.title || "Untitled task"}</h2>
      )}

      <div className="task-meta-wrapper" ref={pickerRef}>
        <button
          className="task-meta"
          type="button"
          onClick={handleCategoryClick}
          onContextMenu={(e) => {
            e.preventDefault();
            e.stopPropagation();
            setDirectColorOpen((v) => !v);
          }}
        >
          {item.category}
        </button>
        {directColorOpen && (
          <InlineColorPopover
            anchorSelector=".task-meta"
            wrapperRef={pickerRef}
            currentColor={color}
            customColors={customColors}
            onPick={(c) => onSetCategoryColor?.(item.category, c)}
            onCommitCustom={(c) => onRememberCustomColor?.(c)}
            onClose={() => setDirectColorOpen(false)}
          />
        )}
        {item.notes.trim() && (
          <span className="notes-indicator">notes</span>
        )}
        {showCategoryPicker && (
          <div className="category-picker">
            {categories.map((cat) => {
              const isRenamingRow = renamingCatInPicker === cat;
              const commitRow = () => {
                const trimmed = renameCatDraft.trim();
                setRenamingCatInPicker(null);
                setRenameCatDraft("");
                if (trimmed && trimmed !== cat) onRenameCategory?.(cat, trimmed);
              };

              return (
                <div key={cat} className="category-option-row">
                  {isRenamingRow ? (
                    <input
                      autoFocus
                      className="inline-add-input category-rename-input"
                      value={renameCatDraft}
                      onChange={(e) => setRenameCatDraft(e.target.value)}
                      onBlur={commitRow}
                      onClick={(e) => e.stopPropagation()}
                      onMouseDown={(e) => e.stopPropagation()}
                      onKeyDown={(e) => {
                        e.stopPropagation();
                        if (e.key === "Enter") commitRow();
                        else if (e.key === "Escape") { setRenamingCatInPicker(null); setRenameCatDraft(""); }
                      }}
                    />
                  ) : (
                    <button
                      className={cat === item.category ? "category-option active" : "category-option"}
                      type="button"
                      onClick={(e) => { e.stopPropagation(); handlePickCategory(cat); }}
                    >
                      <span className="category-dot" style={{ background: categoryColor(cat, categoryColors) }} />
                      {cat}
                    </button>
                  )}
                  <button
                    className="category-rename-btn"
                    type="button"
                    aria-label={`Rename ${cat}`}
                    onClick={(e) => {
                      e.stopPropagation();
                      setRenamingCatInPicker(cat);
                      setRenameCatDraft(cat);
                    }}
                  >
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.3">
                      <path d="M8 1.5L10.5 4L4 10.5L1.5 10.5L1.5 8L8 1.5Z" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </button>
                  <ColorEditButton
                    category={cat}
                    currentColor={categoryColor(cat, categoryColors)}
                    customColors={customColors}
                    isOpen={editingColorFor === cat}
                    onToggle={() => setEditingColorFor(editingColorFor === cat ? null : cat)}
                    onPick={(c) => onSetCategoryColor?.(cat, c)}
                    onCommitCustom={(c) => onRememberCustomColor?.(c)}
                  />
                </div>
              );
            })}
            <div className="category-picker-divider" />
            {pickerNewCatDraft === null ? (
              <button
                className="category-option new-category"
                type="button"
                onClick={(e) => { e.stopPropagation(); setPickerNewCatDraft(""); }}
              >
                + New Category
              </button>
            ) : (
              <input
                autoFocus
                className="inline-add-input"
                value={pickerNewCatDraft}
                placeholder="Category name"
                onChange={(e) => setPickerNewCatDraft(e.target.value)}
                onBlur={commitPickerNewCategory}
                onClick={(e) => e.stopPropagation()}
                onMouseDown={(e) => e.stopPropagation()}
                onKeyDown={(e) => {
                  e.stopPropagation();
                  if (e.key === "Enter") commitPickerNewCategory();
                  else if (e.key === "Escape") setPickerNewCatDraft(null);
                }}
              />
            )}
          </div>
        )}
      </div>

      {!item.completedAt && onToggleInProgress && (
        <button
          className="progress-btn"
          type="button"
          onClick={(e) => { e.stopPropagation(); onToggleInProgress(item.id); }}
          aria-label={item.status === "inProgress" ? "Mark idle" : "Mark in progress"}
          title={item.status === "inProgress" ? "In progress" : "Mark in progress"}
        >
          <span className="progress-dot" />
        </button>
      )}

      {!item.completedAt && onComplete && (
        <button
          className="complete-btn"
          type="button"
          onClick={(e) => { e.stopPropagation(); onComplete(item.id); }}
          aria-label="Complete item"
        >
          <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 8L6.2 11L12 4.5" />
          </svg>
        </button>
      )}
    </article>
  );
}

function TitleEditor({
  value,
  onChange,
  onCommit,
}: {
  value: string;
  onChange: (v: string) => void;
  onCommit: () => void;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.focus();
    const end = el.value.length;
    el.setSelectionRange(end, end);
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [value]);

  return (
    <textarea
      ref={ref}
      className="task-title-input"
      value={value}
      rows={1}
      onChange={(e) => onChange(e.target.value)}
      onBlur={onCommit}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          onCommit();
        } else if (e.key === "Escape") {
          onCommit();
        }
      }}
      onClick={(e) => e.stopPropagation()}
      placeholder="Untitled task"
    />
  );
}

function NotesModal({
  title,
  notes,
  onChange,
  onClose,
}: {
  title: string;
  notes: string;
  onChange: (value: string) => void;
  onClose: () => void;
}) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    function handleKey(e: globalThis.KeyboardEvent) {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
      }
    }
    window.addEventListener("keydown", handleKey, true);
    return () => window.removeEventListener("keydown", handleKey, true);
  }, [onClose]);

  // Place cursor at end of existing notes on open
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    const end = el.value.length;
    el.focus();
    el.setSelectionRange(end, end);
  }, []);

  return createPortal(
    <div className="notes-backdrop" onMouseDown={onClose}>
      <div
        className="notes-panel"
        onMouseDown={(e) => e.stopPropagation()}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="notes-header">
          <h2 className="notes-title">{title}</h2>
          <button
            className="notes-close"
            type="button"
            onClick={onClose}
            aria-label="Close"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
              <path d="M3.5 3.5L12.5 12.5M12.5 3.5L3.5 12.5" />
            </svg>
          </button>
        </div>
        <textarea
          ref={textareaRef}
          className="notes-textarea"
          value={notes}
          placeholder="notes"
          onChange={(e) => onChange(e.target.value)}
        />
      </div>
    </div>,
    document.body,
  );
}

function ProjectSelect({
  projects,
  activeId,
  isActive,
  onSelect,
  onNavigate,
  onRequestNewProject,
}: {
  projects: GardenProject[];
  activeId: string;
  isActive: boolean;
  onSelect: (id: string) => void;
  onNavigate: () => void;
  onRequestNewProject: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [coords, setCoords] = useState<{ top: number; left: number; width: number } | null>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const active = projects.find((p) => p.id === activeId);

  useEffect(() => {
    if (!open || !wrapperRef.current) return;
    const rect = wrapperRef.current.getBoundingClientRect();
    setCoords({ top: rect.bottom + 6, left: rect.left, width: rect.width });
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function handleOutside(e: PointerEvent) {
      if (menuRef.current?.contains(e.target as Node)) return;
      if (wrapperRef.current?.contains(e.target as Node)) return;
      setOpen(false);
    }
    window.addEventListener("pointerdown", handleOutside, true);
    return () => window.removeEventListener("pointerdown", handleOutside, true);
  }, [open]);

  const pillClass = [
    "project-pill",
    open && "open",
    isActive && "active",
  ].filter(Boolean).join(" ");

  return (
    <>
      <div ref={wrapperRef} className={pillClass}>
        <button
          type="button"
          className="project-pill-name"
          onClick={(e) => { e.stopPropagation(); onNavigate(); setOpen(false); }}
        >
          <span className="project-select-label">{active?.name ?? "Select project"}</span>
        </button>
        <button
          type="button"
          className="project-pill-chevron"
          onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }}
          aria-label="Switch project"
        >
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M3 4.5L6 7.5L9 4.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>
      {open && coords && createPortal(
        <div
          ref={menuRef}
          className="project-select-menu"
          style={{ position: "fixed", top: coords.top, left: coords.left, minWidth: coords.width }}
          onClick={(e) => e.stopPropagation()}
          onMouseDown={(e) => e.stopPropagation()}
        >
          {projects.map((p) => (
            <button
              key={p.id}
              type="button"
              className={p.id === activeId ? "project-select-option active" : "project-select-option"}
              onClick={() => { onSelect(p.id); setOpen(false); }}
            >
              <span>{p.name}</span>
              {p.id === activeId && (
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.8">
                  <path d="M2.5 6.5L5 9L9.5 3.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>
          ))}
          <div className="project-select-divider" />
          <button
            type="button"
            className="project-select-option new-project"
            onClick={() => { setOpen(false); onRequestNewProject(); }}
          >
            + New Garden
          </button>
        </div>,
        document.body,
      )}
    </>
  );
}

function SidebarCategoryRow({
  category,
  color,
  customColors,
  count,
  isActive,
  isColorPickerOpen,
  onSelect,
  onStartRename,
  onToggleColorPicker,
  onCloseColorPicker,
  onPickColor,
  onCommitCustomColor,
}: {
  category: string;
  color: string;
  customColors: string[];
  count: number;
  isActive: boolean;
  isColorPickerOpen: boolean;
  onSelect: () => void;
  onStartRename: () => void;
  onToggleColorPicker: () => void;
  onCloseColorPicker: () => void;
  onPickColor: (color: string) => void;
  onCommitCustomColor: (color: string) => void;
}) {
  const rowRef = useRef<HTMLDivElement>(null);

  return (
    <div
      ref={rowRef}
      className={isActive ? "sidebar-link sidebar-category-row active" : "sidebar-link sidebar-category-row"}
      onContextMenu={(e) => { e.preventDefault(); onStartRename(); }}
    >
      <button
        type="button"
        className="category-dot-btn"
        onClick={(e) => { e.stopPropagation(); onToggleColorPicker(); }}
        aria-label={`Change color for ${category}`}
      >
        <span className="category-dot" style={{ background: color }} />
      </button>
      <button
        type="button"
        className="sidebar-category-label-btn"
        onClick={() => { onCloseColorPicker(); onSelect(); }}
      >
        <span className="sidebar-category-label-text">{category}</span>
        <span>{count}</span>
      </button>
      {isColorPickerOpen && (
        <InlineColorPopover
          anchorSelector=".category-dot-btn"
          wrapperRef={rowRef}
          currentColor={color}
          customColors={customColors}
          onPick={onPickColor}
          onCommitCustom={onCommitCustomColor}
          onClose={onCloseColorPicker}
        />
      )}
    </div>
  );
}

function InlineColorPopover({
  anchorSelector,
  wrapperRef,
  currentColor,
  customColors,
  onPick,
  onCommitCustom,
  onClose,
}: {
  anchorSelector: string;
  wrapperRef: React.RefObject<HTMLDivElement | null>;
  currentColor: string;
  customColors: string[];
  onPick: (color: string) => void;
  onCommitCustom: (color: string) => void;
  onClose: () => void;
}) {
  const nativeInputRef = useRef<HTMLInputElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const commitTimerRef = useRef<number | null>(null);
  const [coords, setCoords] = useState<{ top: number; left: number } | null>(null);

  useEffect(() => {
    const anchor = wrapperRef.current?.querySelector<HTMLElement>(anchorSelector);
    if (!anchor) return;
    const rect = anchor.getBoundingClientRect();
    setCoords({ top: rect.bottom + 6, left: rect.left });
  }, [anchorSelector, wrapperRef]);

  useEffect(() => () => {
    if (commitTimerRef.current) window.clearTimeout(commitTimerRef.current);
  }, []);

  useEffect(() => {
    function handleOutside(e: PointerEvent) {
      if (popoverRef.current?.contains(e.target as Node)) return;
      if (wrapperRef.current?.contains(e.target as Node)) return;
      onClose();
    }
    window.addEventListener("pointerdown", handleOutside, true);
    return () => window.removeEventListener("pointerdown", handleOutside, true);
  }, [onClose, wrapperRef]);

  if (!coords) return null;

  const renderSwatch = (c: string) => (
    <button
      key={c}
      className={currentColor.toLowerCase() === c.toLowerCase() ? "color-swatch active" : "color-swatch"}
      type="button"
      style={{ background: c }}
      onClick={(e) => { e.stopPropagation(); onPick(c); }}
      aria-label={c}
    />
  );

  return createPortal(
    <div
      ref={popoverRef}
      className="color-swatch-picker"
      style={{ position: "fixed", top: coords.top, left: coords.left }}
      onClick={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
    >
      {customColors.length > 0 && (
        <>
          <div className="color-swatch-row">{customColors.map(renderSwatch)}</div>
          <div className="color-swatch-divider" />
        </>
      )}
      <div className="color-swatch-row">{colorPalette.map(renderSwatch)}</div>
      <div className="color-swatch-divider" />
      <button
        className="color-swatch-more"
        type="button"
        onClick={(e) => { e.stopPropagation(); nativeInputRef.current?.click(); }}
      >
        <span className="color-swatch-more-swatch" />
        Show more colors…
      </button>
      <input
        ref={nativeInputRef}
        type="color"
        className="color-swatch-native-input"
        defaultValue={currentColor}
        onChange={(e) => {
          const val = e.target.value;
          onPick(val);
          if (commitTimerRef.current) window.clearTimeout(commitTimerRef.current);
          commitTimerRef.current = window.setTimeout(() => onCommitCustom(val), 700);
        }}
        onClick={(e) => e.stopPropagation()}
      />
    </div>,
    document.body,
  );
}

function ColorEditButton({
  category,
  currentColor,
  customColors,
  isOpen,
  onToggle,
  onPick,
  onCommitCustom,
}: {
  category: string;
  currentColor: string;
  customColors: string[];
  isOpen: boolean;
  onToggle: () => void;
  onPick: (color: string) => void;
  onCommitCustom: (color: string) => void;
}) {
  const btnRef = useRef<HTMLButtonElement>(null);
  const nativeInputRef = useRef<HTMLInputElement>(null);
  const commitTimerRef = useRef<number | null>(null);
  const [coords, setCoords] = useState<{ top: number; left: number } | null>(null);

  useEffect(() => {
    if (!isOpen || !btnRef.current) {
      setCoords(null);
      return;
    }
    const rect = btnRef.current.getBoundingClientRect();
    setCoords({ top: rect.top, left: rect.right + 6 });
  }, [isOpen]);

  const renderSwatch = (c: string) => (
    <button
      key={c}
      className={currentColor.toLowerCase() === c.toLowerCase() ? "color-swatch active" : "color-swatch"}
      type="button"
      style={{ background: c }}
      onClick={(e) => { e.stopPropagation(); onPick(c); }}
      aria-label={c}
    />
  );

  return (
    <>
      <button
        ref={btnRef}
        className="color-edit-btn"
        type="button"
        onClick={(e) => { e.stopPropagation(); onToggle(); }}
        aria-label={`Change color for ${category}`}
      >
        <span className="color-edit-dot" style={{ background: currentColor }} />
      </button>
      {isOpen && coords && createPortal(
        <div
          className="color-swatch-picker"
          style={{ position: "fixed", top: coords.top, left: coords.left }}
          onClick={(e) => e.stopPropagation()}
          onMouseDown={(e) => e.stopPropagation()}
        >
          {customColors.length > 0 && (
            <>
              <div className="color-swatch-row">
                {customColors.map(renderSwatch)}
              </div>
              <div className="color-swatch-divider" />
            </>
          )}
          <div className="color-swatch-row">
            {colorPalette.map(renderSwatch)}
          </div>
          <div className="color-swatch-divider" />
          <button
            className="color-swatch-more"
            type="button"
            onClick={(e) => { e.stopPropagation(); nativeInputRef.current?.click(); }}
          >
            <span className="color-swatch-more-swatch" />
            Show more colors…
          </button>
          <input
            ref={nativeInputRef}
            type="color"
            className="color-swatch-native-input"
            defaultValue={currentColor}
            onChange={(e) => {
              const val = e.target.value;
              onPick(val);
              if (commitTimerRef.current) window.clearTimeout(commitTimerRef.current);
              commitTimerRef.current = window.setTimeout(() => onCommitCustom(val), 700);
            }}
            onClick={(e) => e.stopPropagation()}
          />
        </div>,
        document.body,
      )}
    </>
  );
}

export default App;
