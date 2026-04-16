export type GardenItem = {
  id: string;
  title: string;
  notes: string;
  category: string;
  priority: number;
  priorityBucket: number;
  createdAt: string;
  completedAt: string | null;
};

export type GardenProject = {
  id: string;
  name: string;
  categories: string[];
  categoryColors: Record<string, string>;
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
