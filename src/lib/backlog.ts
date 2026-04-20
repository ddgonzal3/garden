import type { GardenItem, GardenProject, ItemStatus } from "../types";

export const colorPalette = [
  "#7a2f3a",  // deep maroon (Crossfades)
  "#8a3a38",  // crimson (Comp sound)
  "#8a4a35",  // rust orange (Losing variations)
  "#8a5a3a",  // warm brown (Suppress outputs)
  "#7a2e2e",  // oxblood
  "#8a3630",  // burnt red
  "#6a5a3a",  // olive brown
  "#6a7d5a",  // olive green (Internal timeline)
  "#4a6a4a",  // forest
  "#3f7a7a",  // teal (Clarification)
  "#4e6578",  // slate blue (GenAI)
  "#5b6a7a",  // muted blue-gray (Uncategorized)
  "#5d7390",  // cool slate (Warp markers)
  "#3a4a5e",  // deep navy slate
  "#5f4a6e",  // muted purple (APIs)
  "#6a4a78",  // plum
  "#7a5bb5",  // vivid purple (in-progress badge)
  "#4a3e5e",  // indigo
  "#7a3e35",  // maroon-red (DAW)
  "#4a2e35",  // dark wine
  "#6a4030",  // mahogany
  "#3a5e5e",  // dark teal
  "#4a5a4a",  // moss
  "#3e4a58",  // charcoal blue
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

export const DEFAULT_BUCKET_NAMES = ["Now", "Later", "Someday", "Vibes"];

export function bucketLabel(project: GardenProject, bucket: number): string {
  return project.bucketNames[bucket] ?? `P${bucket + 1}`;
}

export function createProject(name: string): GardenProject {
  return {
    id: crypto.randomUUID(),
    name,
    categories: ["Uncategorized"],
    categoryColors: {},
    customColors: [],
    items: [],
    priorityBucketCount: 4,
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

  const customColors = Array.isArray(raw.customColors)
    ? (raw.customColors as string[]).filter((c) => typeof c === "string")
    : [];

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
    customColors,
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
