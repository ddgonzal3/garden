export type ItemStatus = "idle" | "inProgress";

export type GardenItem = {
  id: string;
  title: string;
  notes: string;
  category: string;
  priority: number;
  priorityBucket: number;
  createdAt: string;
  completedAt: string | null;
  status: ItemStatus;
};

export type GardenProject = {
  id: string;
  name: string;
  categories: string[];
  categoryColors: Record<string, string>;
  customColors: string[];
  items: GardenItem[];
  priorityBucketCount: number;
  bucketNames: string[];
};

export type Backlog = {
  projects: GardenProject[];
  activeProjectId: string | null;
};

export type SidebarSelection =
  | { type: "priorityBoard" }
  | { type: "all" }
  | { type: "completed" }
  | { type: "category"; category: string };
