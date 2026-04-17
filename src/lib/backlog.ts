import type { GardenItem, GardenProject, ItemStatus } from "../types";

export const colorPalette = [
  "#C86040",
  "#D0A050",
  "#B8C040",
  "#A0D050",
  "#60D890",
  "#50B8B0",
  "#68A8C0",
  "#7888C8",
  "#9080D0",
  "#B068D0",
  "#C830A0",
  "#D85088",
  "#C07030",
  "#90A870",
  "#68A880",
  "#30A098",
  "#8098A8",
  "#7870A0",
  "#905888",
  "#5C2D5C",
  "#287070",
  "#5838B8",
  "#804828",
  "#507848",
];

export function categoryColor(
  category: string,
  categoryColors?: Record<string, string>,
): string {
  if (categoryColors?.[category]) {
    return categoryColors[category];
  }

  if (category === "Uncategorized") {
    return "#8098A8";
  }

  let hash = 0;
  for (let index = 0; index < category.length; index += 1) {
    hash = (hash << 5) - hash + category.charCodeAt(index);
    hash |= 0;
  }

  return colorPalette[Math.abs(hash) % colorPalette.length];
}

export const DEFAULT_BUCKET_NAMES = ["Now", "Later", "Someday"];

export function bucketLabel(project: GardenProject, bucket: number): string {
  return project.bucketNames[bucket] ?? `P${bucket + 1}`;
}

export function createProject(name: string): GardenProject {
  return {
    id: crypto.randomUUID(),
    name,
    categories: ["Uncategorized"],
    categoryColors: {},
    items: [],
    priorityBucketCount: 3,
    bucketNames: [...DEFAULT_BUCKET_NAMES],
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
          status: (item.status as ItemStatus) === "inProgress" ? "inProgress" : "idle",
        }),
      )
    : [];

  const categories = Array.isArray(raw.categories) && raw.categories.length > 0
    ? (raw.categories as string[])
    : ["Uncategorized"];

  const categoryColors =
    raw.categoryColors && typeof raw.categoryColors === "object" && !Array.isArray(raw.categoryColors)
      ? (raw.categoryColors as Record<string, string>)
      : {};

  const bucketCount = (raw.priorityBucketCount as number) ?? 3;
  const rawNames = Array.isArray(raw.bucketNames) ? (raw.bucketNames as string[]) : [];
  const bucketNames = Array.from({ length: bucketCount }, (_, i) =>
    rawNames[i] ?? DEFAULT_BUCKET_NAMES[i] ?? `P${i + 1}`,
  );

  return {
    id: (raw.id as string) ?? crypto.randomUUID(),
    name: (raw.name as string) ?? "Untitled Project",
    categories,
    categoryColors,
    items,
    priorityBucketCount: bucketCount,
    bucketNames,
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
