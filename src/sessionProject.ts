import { existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { JsonObject } from './types';

const PROJECT_MARKERS = [
  '.git',
  'package.json',
  'pnpm-workspace.yaml',
  'pubspec.yaml',
  'Cargo.toml',
  'go.mod',
  '.github/copilot-instructions.md',
];

const INSTRUCTION_FILE_NAMES = new Set([
  'global.instructions.md',
  'stack-override.instructions.md',
  'readonly.instructions.md',
  'git.instructions.md',
  'copilot-instructions.md',
]);


const WORKSPACE_STORAGE_SEGMENT = `${path.sep}appdata${path.sep}roaming${path.sep}code - insiders${path.sep}user${path.sep}workspacestorage${path.sep}`;

export interface SessionProjectState {
  workspaceId: string | null;
  projectKey: string;
  projectName: string;
  projectPath: string | null;
}

function isJsonObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function normalizeFileUrl(value: unknown): string | null {
  if (typeof value !== 'string' || !value.startsWith('file://')) {
    return null;
  }

  try {
    return path.normalize(fileURLToPath(value));
  } catch {
    return null;
  }
}

function normalizeAbsolutePath(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (/^[A-Za-z]:[\\/]/.test(trimmed)) {
    return path.normalize(trimmed);
  }

  if (/^\/[A-Za-z]:\//.test(trimmed)) {
    return path.normalize(trimmed.slice(1).replace(/\//g, path.sep));
  }

  return null;
}

function normalizeCandidatePath(value: unknown): string | null {
  return normalizeFileUrl(value) ?? normalizeAbsolutePath(value);
}

function shouldIgnoreCandidate(candidatePath: string): boolean {
  const normalized = candidatePath.toLowerCase();
  if (normalized.includes(WORKSPACE_STORAGE_SEGMENT)) {
    return true;
  }

  return normalized.includes(`${path.sep}chatsessions${path.sep}`);
}

function addCandidatePath(target: Set<string>, candidate: string | null) {
  if (!candidate || shouldIgnoreCandidate(candidate)) {
    return;
  }

  target.add(candidate);
}

function collectCandidatePaths(value: unknown, target: Set<string>, depth: number = 0) {
  if (depth > 10) {
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      collectCandidatePaths(item, target, depth + 1);
    }
    return;
  }

  if (!isJsonObject(value)) {
    return;
  }

  addCandidatePath(target, normalizeCandidatePath(value.fsPath));
  addCandidatePath(target, normalizeCandidatePath(value.filePath));
  addCandidatePath(target, normalizeFileUrl(value.external));

  if (value.scheme === 'file') {
    addCandidatePath(target, normalizeCandidatePath(value.path));
  }

  for (const nestedValue of Object.values(value)) {
    collectCandidatePaths(nestedValue, target, depth + 1);
  }
}

function getSearchStartPath(candidatePath: string): string {
  try {
    if (existsSync(candidatePath)) {
      const stats = statSync(candidatePath);
      return stats.isDirectory() ? candidatePath : path.dirname(candidatePath);
    }
  } catch {
    // Fall back to heuristics below.
  }

  return path.extname(candidatePath) ? path.dirname(candidatePath) : candidatePath;
}

function findProjectRoot(candidatePath: string): string | null {
  let current = getSearchStartPath(candidatePath);

  while (true) {
    for (const marker of PROJECT_MARKERS) {
      if (existsSync(path.join(current, marker))) {
        return current;
      }
    }

    const parent = path.dirname(current);
    if (parent === current) {
      return null;
    }

    current = parent;
  }
}

function isInstructionLikePath(candidatePath: string): boolean {
  const fileName = path.basename(candidatePath).toLowerCase();
  return INSTRUCTION_FILE_NAMES.has(fileName);
}

function scoreProjectRoots(candidatePaths: Iterable<string>): string | null {
  const rootScores = new Map<string, { score: number; uniquePaths: Set<string> }>();

  for (const candidatePath of candidatePaths) {
    const projectRoot = findProjectRoot(candidatePath);
    if (!projectRoot) {
      continue;
    }

    const entry = rootScores.get(projectRoot) ?? { score: 0, uniquePaths: new Set<string>() };
    if (entry.uniquePaths.has(candidatePath)) {
      rootScores.set(projectRoot, entry);
      continue;
    }

    entry.uniquePaths.add(candidatePath);

    const relativeParts = path.relative(projectRoot, candidatePath).split(path.sep).filter(Boolean);
    const instructionLike = isInstructionLikePath(candidatePath);
    entry.score += instructionLike ? 1 : 3;

    if (!instructionLike && relativeParts.length >= 2) {
      entry.score += 1;
    }

    rootScores.set(projectRoot, entry);
  }

  let bestRoot: string | null = null;
  let bestScore = Number.NEGATIVE_INFINITY;

  for (const [projectRoot, entry] of rootScores.entries()) {
    const tieBreaker = projectRoot.split(path.sep).filter(Boolean).length / 1000;
    const totalScore = entry.score + tieBreaker;
    if (totalScore > bestScore) {
      bestRoot = projectRoot;
      bestScore = totalScore;
    }
  }

  return bestRoot;
}

export function detectProjectPathFromEvents(events: JsonObject[]): string | null {
  const candidatePaths = new Set<string>();

  for (const event of events) {
    collectCandidatePaths(event, candidatePaths);
  }

  return scoreProjectRoots(candidatePaths);
}

function getProjectNameFromPath(projectPath: string): string {
  return path.basename(projectPath) || projectPath;
}

function getFallbackProjectName(workspaceId: string | null): string {
  if (workspaceId) {
    return `Workspace ${workspaceId.slice(0, 8)}`;
  }

  return 'Sin proyecto detectado';
}

export function mergeSessionProjectInfo(
  currentState: SessionProjectState | null | undefined,
  events: JsonObject[],
  workspaceId: string | null | undefined,
): SessionProjectState {
  const nextWorkspaceId = workspaceId ?? currentState?.workspaceId ?? null;
  const detectedProjectPath = detectProjectPathFromEvents(events) ?? currentState?.projectPath ?? null;

  if (detectedProjectPath) {
    return {
      workspaceId: nextWorkspaceId,
      projectKey: `path:${detectedProjectPath.toLowerCase()}`,
      projectName: getProjectNameFromPath(detectedProjectPath),
      projectPath: detectedProjectPath,
    };
  }

  return {
    workspaceId: nextWorkspaceId,
    projectKey: nextWorkspaceId ? `workspace:${nextWorkspaceId}` : currentState?.projectKey ?? 'unknown',
    projectName: currentState?.projectName ?? getFallbackProjectName(nextWorkspaceId),
    projectPath: currentState?.projectPath ?? null,
  };
}