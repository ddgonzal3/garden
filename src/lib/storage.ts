/**
 * File-based persistence via Tauri's fs plugin.
 *
 * Layout:
 *   ~/.garden/state.json           — { activeProjectId }
 *   ~/.garden/projects/<slug>.json — one file per project
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
import type { Backlog, GardenProject } from "../types";

let gardenDir: string | null = null;

async function getGardenDir(): Promise<string> {
  if (gardenDir) return gardenDir;
  const home = await homeDir();
  gardenDir = await join(home, ".garden");
  return gardenDir;
}

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
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
    return JSON.parse(await readTextFile(path));
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
  return `${slugify(project.name)}.json`;
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
      const raw = await readTextFile(`${dir}/${entry.name}`);
      projects.push(JSON.parse(raw));
    } catch {
      // skip corrupt files
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
    if (!raw?.projects?.length) return null;

    const backlog: Backlog = {
      projects: raw.projects,
      activeProjectId: raw.activeProjectId ?? raw.projects[0].id,
    };

    // Write each project to its own file
    await ensureProjectsDir();
    for (const project of backlog.projects) {
      await writeProject(project);
    }

    // Write state
    await writeState({ activeProjectId: backlog.activeProjectId! });

    // Rename legacy file so we don't migrate again
    await rename(legacyPath, `${dir}/backlog.json.migrated`);

    return backlog;
  } catch {
    return null;
  }
}

// ── Public API ───────────────────────────────────────────────────

export async function loadBacklog(): Promise<Backlog> {
  console.log("[storage] loadBacklog starting...");
  const dir = await getGardenDir();
  console.log("[storage] gardenDir:", dir);

  const projectsDir = await ensureProjectsDir();
  console.log("[storage] projectsDir:", projectsDir);

  const dirEntries = await readDir(projectsDir);
  console.log("[storage] project files:", dirEntries.map((e) => e.name));
  const hasProjects = dirEntries.some((e) => e.name?.endsWith(".json"));

  // If no project files exist, try migrating from legacy format
  if (!hasProjects) {
    console.log("[storage] no projects found, attempting migration...");
    const migrated = await migrateLegacyBacklog();
    if (migrated) {
      console.log("[storage] migration complete, projects:", migrated.projects.map((p) => p.name));
      return migrated;
    }
    console.log("[storage] migration returned null");
  }

  const projects = await readAllProjects();
  const state = await readState();
  console.log("[storage] loaded", projects.length, "projects, state:", state);

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

export async function renameProjectFile(
  oldProject: GardenProject,
  newProject: GardenProject,
): Promise<void> {
  if (slugify(oldProject.name) !== slugify(newProject.name)) {
    await deleteProjectFile(oldProject);
  }
  await writeProject(newProject);
}
