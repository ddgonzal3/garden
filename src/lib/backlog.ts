import type { Backlog, GardenItem, GardenProject } from "../types";

const STORAGE_KEY = "garden:web:backlog";

const colorPalette = [
  "#70cfc0",
  "#e6b564",
  "#8baef4",
  "#df9b69",
  "#8fd099",
  "#c3c9d2",
  "#b59ef1",
  "#f08ca8",
];

export function categoryColor(category: string): string {
  if (category === "Uncategorized") {
    return "#adb5c0";
  }

  let hash = 0;
  for (let index = 0; index < category.length; index += 1) {
    hash = (hash << 5) - hash + category.charCodeAt(index);
    hash |= 0;
  }

  return colorPalette[Math.abs(hash) % colorPalette.length];
}

export function createProject(name: string): GardenProject {
  return {
    id: crypto.randomUUID(),
    name,
    categories: ["Uncategorized"],
    items: [],
    priorityBucketCount: 3,
  };
}

export function createSeedBacklog(): Backlog {
  const project = createProject("Garden");
  const seedItems: Array<Partial<GardenItem> & Pick<GardenItem, "title" | "category" | "priorityBucket" | "priority">> = [
    {
      title: "Losing variations when find-like-this on a clip with variations",
      category: "Variations",
      priorityBucket: 0,
      priority: 0,
    },
    {
      title: "Comp sound with variations not reflecting in panel",
      category: "Variations",
      priorityBucket: 0,
      priority: 1,
    },
    {
      title: "Duplicate sections x canvas",
      category: "DAW",
      priorityBucket: 0,
      priority: 2,
    },
    {
      title: "Track headers should keep a fixed width and never resize horizontally",
      category: "Design",
      priorityBucket: 0,
      priority: 3,
    },
    {
      title: "Stretch: Shift for Ableton, Option for Logic",
      category: "DAW",
      priorityBucket: 1,
      priority: 0,
    },
    {
      title: "Warp markers",
      category: "Clip Editor",
      priorityBucket: 1,
      priority: 1,
    },
    {
      title: "Load Serum preset for bassline",
      category: "Plugins",
      priorityBucket: 1,
      priority: 2,
    },
    {
      title: "Scrollable foots when catalog expands such that the text gets cut off",
      category: "Clip Editor",
      priorityBucket: 2,
      priority: 0,
    },
  ];

  project.categories = Array.from(
    new Set(["Uncategorized", ...seedItems.map((item) => item.category)]),
  );

  project.items = seedItems.map((item) => ({
    id: crypto.randomUUID(),
    title: item.title,
    notes: "",
    category: item.category,
    priority: item.priority,
    priorityBucket: item.priorityBucket,
    createdAt: new Date().toISOString(),
    completedAt: null,
  }));

  return {
    projects: [project],
    activeProjectId: project.id,
  };
}

export function normalizeBacklog(raw: unknown): Backlog {
  const fallback = createSeedBacklog();

  if (!raw || typeof raw !== "object") {
    return fallback;
  }

  const maybeBacklog = raw as Partial<Backlog> & {
    items?: GardenItem[];
    categories?: string[];
  };

  if (Array.isArray(maybeBacklog.projects) && maybeBacklog.projects.length > 0) {
    return {
      projects: maybeBacklog.projects.map((project) => ({
        id: project.id ?? crypto.randomUUID(),
        name: project.name ?? "Untitled Project",
        categories: project.categories?.length ? project.categories : ["Uncategorized"],
        priorityBucketCount: project.priorityBucketCount ?? 3,
        items: Array.isArray(project.items)
          ? project.items.map((item) => ({
              id: item.id ?? crypto.randomUUID(),
              title: item.title ?? "",
              notes: item.notes ?? "",
              category: item.category ?? "Uncategorized",
              priority: item.priority ?? 0,
              priorityBucket: item.priorityBucket ?? 0,
              createdAt: item.createdAt ?? new Date().toISOString(),
              completedAt: item.completedAt ?? null,
            }))
          : [],
      })),
      activeProjectId:
        maybeBacklog.activeProjectId ??
        maybeBacklog.projects[0]?.id ??
        fallback.activeProjectId,
    };
  }

  if (Array.isArray(maybeBacklog.items)) {
    const project = createProject("Flow");
    project.categories = maybeBacklog.categories?.length
      ? maybeBacklog.categories
      : ["Uncategorized"];
    project.items = maybeBacklog.items;
    return {
      projects: [project],
      activeProjectId: project.id,
    };
  }

  return fallback;
}

export function loadBacklog(): Backlog {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? normalizeBacklog(JSON.parse(stored)) : createSeedBacklog();
  } catch {
    return createSeedBacklog();
  }
}

export function saveBacklog(backlog: Backlog): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(backlog));
}

export function getActiveProject(backlog: Backlog): GardenProject {
  return (
    backlog.projects.find((project) => project.id === backlog.activeProjectId) ??
    backlog.projects[0]
  );
}

export function getActiveItems(project: GardenProject): GardenItem[] {
  return project.items
    .filter((item) => item.completedAt === null)
    .sort((left, right) => {
      if (left.priorityBucket !== right.priorityBucket) {
        return left.priorityBucket - right.priorityBucket;
      }

      return left.priority - right.priority;
    });
}

export function getCompletedItems(project: GardenProject): GardenItem[] {
  return project.items
    .filter((item) => item.completedAt !== null)
    .sort((left, right) => {
      return (right.completedAt ?? "").localeCompare(left.completedAt ?? "");
    });
}

export function getItemsInCategory(project: GardenProject, category: string): GardenItem[] {
  return getActiveItems(project).filter((item) => item.category === category);
}

export function getItemsInBucket(project: GardenProject, bucket: number): GardenItem[] {
  return getActiveItems(project).filter((item) => item.priorityBucket === bucket);
}
