import path from 'node:path';
import { createObserverDatabase, type ObserverDatabase } from './db';
import { discoverSourcePaths, listChatSessionFiles, listSessionDirectories } from './paths';
import { readSession } from './readSession';

export interface ScanSummary {
  scannedSessions: number;
  loadedEvents: number;
  errors: number;
  source: string;
}

export async function scanSessions(options: {
  db: ObserverDatabase;
  sessionStateRoot?: string | null;
  workspaceStorageRoot?: string | null;
}): Promise<ScanSummary> {
  const discovered = await discoverSourcePaths();
  const workspaceStorageRoot = options.workspaceStorageRoot ?? discovered.workspaceStorageRoot;
  const sessionStateRoot = options.sessionStateRoot ?? discovered.sessionStateRoot;

  // Prefer workspaceStorage over legacy session-state
  if (workspaceStorageRoot) {
    const sessionFiles = await listChatSessionFiles(workspaceStorageRoot);
    let loadedEvents = 0;
    let errors = 0;

    for (const file of sessionFiles) {
      try {
        const events = await readSession(file.filePath);
        options.db.replaceSession(file.sessionId, events, {
          workspaceId: file.workspaceId,
        });
        loadedEvents += events.length;
      } catch (error) {
        errors += 1;
        console.error(`[scanSessions] Failed to ingest ${file.filePath}:`, error);
      }
    }

    return {
      scannedSessions: sessionFiles.length,
      loadedEvents,
      errors,
      source: 'workspaceStorage/chatSessions',
    };
  }

  // Fallback to legacy session-state
  if (sessionStateRoot) {
    const sessionDirs = await listSessionDirectories(sessionStateRoot);
    let loadedEvents = 0;
    let errors = 0;

    for (const sessionDir of sessionDirs) {
      try {
        const events = await readSession(sessionDir);
        options.db.replaceSession(path.basename(sessionDir), events);
        loadedEvents += events.length;
      } catch (error) {
        errors += 1;
        console.error(`[scanSessions] Failed to ingest ${sessionDir}:`, error);
      }
    }

    return {
      scannedSessions: sessionDirs.length,
      loadedEvents,
      errors,
      source: 'session-state (legacy)',
    };
  }

  console.warn('[scanSessions] Neither workspaceStorage nor session-state root found.');
  return {
    scannedSessions: 0,
    loadedEvents: 0,
    errors: 0,
    source: 'none',
  };
}

async function runFromCli(): Promise<void> {
  const db = createObserverDatabase();

  try {
    const result = await scanSessions({ db });
    console.log(JSON.stringify(result, null, 2));
    console.log(`events_total=${db.countEvents()}`);
  } finally {
    db.close();
  }
}

if (require.main === module) {
  void runFromCli().catch((error: unknown) => {
    console.error('[scanSessions] Fatal error:', error);
    process.exitCode = 1;
  });
}