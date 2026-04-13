import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export interface DiscoveredPaths {
  sessionStateRoot: string | null;
  workspaceStorageRoot: string | null;
  copilotChatRoots: string[];
  transcriptRoots: string[];
}

export async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export function getDefaultSessionStateCandidate(): string {
  return path.join(os.homedir(), '.copilot', 'session-state');
}

export function getDefaultWorkspaceStorageCandidate(): string {
  const appDataRoot = process.env.APPDATA ?? path.join(os.homedir(), 'AppData', 'Roaming');
  return path.join(appDataRoot, 'Code - Insiders', 'User', 'workspaceStorage');
}

export async function discoverSourcePaths(): Promise<DiscoveredPaths> {
  const sessionStateCandidate = getDefaultSessionStateCandidate();
  const workspaceStorageCandidate = getDefaultWorkspaceStorageCandidate();

  const sessionStateRoot = (await pathExists(sessionStateCandidate)) ? sessionStateCandidate : null;
  const workspaceStorageRoot = (await pathExists(workspaceStorageCandidate))
    ? workspaceStorageCandidate
    : null;

  const copilotChatRoots: string[] = [];
  const transcriptRoots: string[] = [];

  if (workspaceStorageRoot) {
    try {
      const workspaceEntries = await fs.readdir(workspaceStorageRoot, { withFileTypes: true });
      for (const entry of workspaceEntries) {
        if (!entry.isDirectory()) {
          continue;
        }

        const copilotChatRoot = path.join(workspaceStorageRoot, entry.name, 'GitHub.copilot-chat');
        if (!(await pathExists(copilotChatRoot))) {
          continue;
        }

        copilotChatRoots.push(copilotChatRoot);

        const transcriptRoot = path.join(copilotChatRoot, 'transcripts');
        if (await pathExists(transcriptRoot)) {
          transcriptRoots.push(transcriptRoot);
        }
      }
    } catch (error) {
      console.error(`[paths] Failed to inspect ${workspaceStorageRoot}:`, error);
    }
  }

  copilotChatRoots.sort();
  transcriptRoots.sort();

  return {
    sessionStateRoot,
    workspaceStorageRoot,
    copilotChatRoots,
    transcriptRoots,
  };
}

export async function listSessionDirectories(sessionStateRoot: string): Promise<string[]> {
  try {
    const entries = await fs.readdir(sessionStateRoot, { withFileTypes: true });
    const sessionPaths: string[] = [];

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }

      const sessionPath = path.join(sessionStateRoot, entry.name);
      const eventsPath = path.join(sessionPath, 'events.jsonl');
      if (await pathExists(eventsPath)) {
        sessionPaths.push(sessionPath);
      }
    }

    sessionPaths.sort();
    return sessionPaths;
  } catch (error) {
    console.error(`[paths] Failed to list sessions in ${sessionStateRoot}:`, error);
    return [];
  }
}

export async function getFileSize(filePath: string): Promise<number | null> {
  try {
    const stats = await fs.stat(filePath);
    return stats.size;
  } catch {
    return null;
  }
}