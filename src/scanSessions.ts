import path from 'node:path';
import { createObserverDatabase, type ObserverDatabase } from './db';
import { discoverSourcePaths, listSessionDirectories } from './paths';
import { readSession } from './readSession';

export interface ScanSummary {
  sessionStateRoot: string | null;
  scannedSessions: number;
  loadedEvents: number;
  errors: number;
}

export async function scanSessions(options: {
  db: ObserverDatabase;
  sessionStateRoot?: string | null;
}): Promise<ScanSummary> {
  const sessionStateRoot = options.sessionStateRoot ?? (await discoverSourcePaths()).sessionStateRoot;

  if (!sessionStateRoot) {
    console.warn('[scanSessions] Session-state root not found.');
    return {
      sessionStateRoot: null,
      scannedSessions: 0,
      loadedEvents: 0,
      errors: 0,
    };
  }

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
    sessionStateRoot,
    scannedSessions: sessionDirs.length,
    loadedEvents,
    errors,
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