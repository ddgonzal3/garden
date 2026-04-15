/**
 * File-based persistence via Tauri's fs plugin.
 *
 * Layout:
 *   ~/.garden/state.json              — { activeProjectId }
 *   ~/.garden/projects/<id>.json      — one file per project (keyed by UUID)
 *
 * On first load, migrates the legacy backlog.json into the new structure.
 */

import {
  readTextFile,
  writeTextFile,
  mkdir,
  exists,
  readDir,
  remove,
  rename,
} from "@tauri-apps/plugin-fs";
import { homeDir, join } from "@tauri-apps/api/path";
import { normalizeProject } from "./backlog";
import type { Backlog, GardenProject } from "../types";

let gardenDir: string | null = null;

async function getGardenDir(): Promise<string> {
  if (gardenDir) return gardenDir;
  const home = await homeDir();
  gardenDir = await join(home, ".garden");
  return gardenDir;
}

// ── State (active project tracking) ──────────────────────────────

type AppState = {
  activeProjectId: string;
};

async function readState(): Promise<AppState | null> {
  const dir = await getGardenDir();
  const path = `${dir}/state.json`;
  if (!(await exists(path))) return null;
  try {
    const parsed = JSON.parse(await readTextFile(path));
    if (parsed && typeof parsed.activeProjectId === "string") {
      return parsed;
    }
    return null;
  } catch {
    return null;
  }
}

async function writeState(state: AppState): Promise<void> {
  const dir = await getGardenDir();
  await writeTextFile(`${dir}/state.json`, JSON.stringify(state, null, 2));
}

// ── Project files ────────────────────────────────────────────────

async function ensureProjectsDir(): Promise<string> {
  const dir = await getGardenDir();
  const projectsDir = `${dir}/projects`;
  if (!(await exists(projectsDir))) {
    await mkdir(projectsDir, { recursive: true });
  }
  return projectsDir;
}

function projectFileName(project: GardenProject): string {
  return `${project.id}.json`;
}

async function writeProject(project: GardenProject): Promise<void> {
  const dir = await ensureProjectsDir();
  await writeTextFile(
    `${dir}/${projectFileName(project)}`,
    JSON.stringify(project, null, 2),
  );
}

async function readAllProjects(): Promise<GardenProject[]> {
  const dir = await ensureProjectsDir();
  const entries = await readDir(dir);
  const projects: GardenProject[] = [];

  for (const entry of entries) {
    if (!entry.name?.endsWith(".json")) continue;
    try {
      const raw = JSON.parse(await readTextFile(`${dir}/${entry.name}`));
      projects.push(normalizeProject(raw));
    } catch {
      console.error(`[storage] skipping corrupt project file: ${entry.name}`);
    }
  }

  return projects;
}

// ── Migration from legacy backlog.json ───────────────────────────

async function migrateLegacyBacklog(): Promise<Backlog | null> {
  const dir = await getGardenDir();
  const legacyPath = `${dir}/backlog.json`;

  if (!(await exists(legacyPath))) return null;

  try {
    const raw = JSON.parse(await readTextFile(legacyPath));
    if (!Array.isArray(raw?.projects) || raw.projects.length === 0) return null;

    const projects = raw.projects.map((p: Record<string, unknown>) => normalizeProject(p));
    const activeProjectId = raw.activeProjectId ?? projects[0].id;

    const backlog: Backlog = { projects, activeProjectId };

    // Write each project to its own file
    await ensureProjectsDir();
    for (const project of projects) {
      await writeProject(project);
    }

    // Write state
    await writeState({ activeProjectId });

    // Rename legacy file so we don't migrate again
    await rename(legacyPath, `${dir}/backlog.json.migrated`);

    return backlog;
  } catch {
    return null;
  }
}

// ── Public API ───────────────────────────────────────────────────

export async function loadBacklog(): Promise<Backlog> {
  const projectsDir = await ensureProjectsDir();
  const dirEntries = await readDir(projectsDir);
  const hasProjects = dirEntries.some((e) => e.name?.endsWith(".json"));

  // If no project files exist, try migrating from legacy format
  if (!hasProjects) {
    const migrated = await migrateLegacyBacklog();
    if (migrated) return migrated;
  }

  const projects = await readAllProjects();
  const state = await readState();

  if (projects.length === 0) {
    return { projects: [], activeProjectId: null };
  }

  const activeProjectId =
    state?.activeProjectId &&
    projects.some((p) => p.id === state.activeProjectId)
      ? state.activeProjectId
      : projects[0].id;

  return { projects, activeProjectId };
}

export async function saveProject(project: GardenProject): Promise<void> {
  await writeProject(project);
}

export async function saveActiveProjectId(id: string): Promise<void> {
  await writeState({ activeProjectId: id });
}

export async function deleteProjectFile(project: GardenProject): Promise<void> {
  const dir = await ensureProjectsDir();
  const path = `${dir}/${projectFileName(project)}`;
  if (await exists(path)) {
    await remove(path);
  }
}
