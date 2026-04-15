import type { GardenItem, GardenProject } from "../types";

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

/** Normalize a raw JSON object into a valid GardenProject, filling missing fields with defaults. */
export function normalizeProject(raw: Record<string, unknown>): GardenProject {
  const items = Array.isArray(raw.items)
    ? (raw.items as Record<string, unknown>[]).map(
        (item): GardenItem => ({
          id: (item.id as string) ?? crypto.randomUUID(),
          title: (item.title as string) ?? "",
          notes: (item.notes as string) ?? "",
          category: (item.category as string) ?? "Uncategorized",
          priority: (item.priority as number) ?? 0,
          priorityBucket: (item.priorityBucket as number) ?? 0,
          createdAt: (item.createdAt as string) ?? new Date().toISOString(),
          completedAt: (item.completedAt as string | null) ?? null,
        }),
      )
    : [];

  const categories = Array.isArray(raw.categories) && raw.categories.length > 0
    ? (raw.categories as string[])
    : ["Uncategorized"];

  return {
    id: (raw.id as string) ?? crypto.randomUUID(),
    name: (raw.name as string) ?? "Untitled Project",
    categories,
    items,
    priorityBucketCount: (raw.priorityBucketCount as number) ?? 3,
  };
}

export function getActiveProject(backlog: { projects: GardenProject[]; activeProjectId: string | null }): GardenProject {
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
