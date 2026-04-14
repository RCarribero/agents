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

export interface SessionFile {
  filePath: string;
  sessionId: string;
  workspaceId: string | null;
}

export function getWorkspaceIdForChatSessionFile(filePath: string): string | null {
  const parentDir = path.dirname(filePath);
  if (path.basename(parentDir).toLowerCase() !== 'chatsessions') {
    return null;
  }

  const workspaceId = path.basename(path.dirname(parentDir));
  return workspaceId || null;
}

export async function listChatSessionFiles(workspaceStorageRoot: string): Promise<SessionFile[]> {
  const sessionFiles: SessionFile[] = [];

  try {
    const workspaceEntries = await fs.readdir(workspaceStorageRoot, { withFileTypes: true });

    for (const workspaceEntry of workspaceEntries) {
      if (!workspaceEntry.isDirectory()) {
        continue;
      }

      const chatSessionsDir = path.join(workspaceStorageRoot, workspaceEntry.name, 'chatSessions');
      const dirExists = await pathExists(chatSessionsDir);
      if (!dirExists) {
        continue;
      }

      try {
        const sessionEntries = await fs.readdir(chatSessionsDir, { withFileTypes: true });

        for (const sessionEntry of sessionEntries) {
          if (sessionEntry.isDirectory()) {
            continue;
          }

          if (!sessionEntry.name.endsWith('.jsonl')) {
            continue;
          }

          const filePath = path.join(chatSessionsDir, sessionEntry.name);
          const sessionId = path.basename(sessionEntry.name, '.jsonl');
          sessionFiles.push({
            filePath,
            sessionId,
            workspaceId: workspaceEntry.name,
          });
        }
      } catch (error) {
        console.error(`[paths] Failed to list session files in ${chatSessionsDir}:`, error);
      }
    }

    sessionFiles.sort((a, b) => a.sessionId.localeCompare(b.sessionId));
  } catch (error) {
    console.error(`[paths] Failed to list workspace entries in ${workspaceStorageRoot}:`, error);
  }

  return sessionFiles;
}

export async function getFileSize(filePath: string): Promise<number | null> {
  try {
    const stats = await fs.stat(filePath);
    return stats.size;
  } catch {
    return null;
  }
}