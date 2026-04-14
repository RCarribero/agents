import { promises as fs } from 'node:fs';
import path from 'node:path';
import type { ObserverDatabase } from './db';
import {
  discoverSourcePaths,
  getFileSize,
  getWorkspaceIdForChatSessionFile,
  listChatSessionFiles,
  listSessionDirectories,
} from './paths';
import { parseEvent } from './parser';
import { readSession } from './readSession';
import type { JsonObject } from './types';

interface FileCursor {
  position: number;
  remainder: string;
}

export interface SessionWatcher {
  close(): Promise<void>;
}

export interface WatcherOptions {
  db: ObserverDatabase;
  sessionStateRoot?: string | null;
  workspaceStorageRoot?: string | null;
  onEvents?: (sessionId: string, events: JsonObject[]) => void;
}

function isSessionFile(filePath: string): boolean {
  const fileName = path.basename(filePath).toLowerCase();
  return fileName === 'events.jsonl' || fileName.endsWith('.jsonl');
}

function extractSessionId(filePath: string): string {
  const fileName = path.basename(filePath);
  if (fileName === 'events.jsonl') {
    // Legacy format: directory name is session ID
    return path.basename(path.dirname(filePath));
  }
  // New format: .jsonl file name (without extension) is session ID
  return path.basename(fileName, '.jsonl');
}

function extractWorkspaceId(filePath: string): string | null {
  return getWorkspaceIdForChatSessionFile(filePath);
}

async function readTextSlice(
  filePath: string,
  position: number,
): Promise<{ content: string; size: number }> {
  const handle = await fs.open(filePath, 'r');

  try {
    const stats = await handle.stat();
    if (stats.size <= position) {
      return {
        content: '',
        size: stats.size,
      };
    }

    const length = stats.size - position;
    const buffer = Buffer.alloc(length);
    await handle.read(buffer, 0, length, position);

    return {
      content: buffer.toString('utf8'),
      size: stats.size,
    };
  } finally {
    await handle.close();
  }
}

export async function startSessionWatcher(options: WatcherOptions): Promise<SessionWatcher> {
  const chokidar = await import('chokidar');
  const cursors = new Map<string, FileCursor>();
  const inFlight = new Map<string, Promise<void>>();

  const discovered = await discoverSourcePaths();
  const workspaceStorageRoot = options.workspaceStorageRoot ?? discovered.workspaceStorageRoot;
  const sessionStateRoot = options.sessionStateRoot ?? discovered.sessionStateRoot;
  const watchPaths: string[] = [];

  // Prefer workspaceStorage
  if (workspaceStorageRoot) {
    const sessionFiles = await listChatSessionFiles(workspaceStorageRoot);
    for (const file of sessionFiles) {
      const size = await getFileSize(file.filePath);
      if (size !== null) {
        cursors.set(file.filePath, { position: size, remainder: '' });
      }
    }

    // Watch all workspace IDs' chatSessions directories
    try {
      const workspaceEntries = await fs.readdir(workspaceStorageRoot, { withFileTypes: true });
      for (const entry of workspaceEntries) {
        if (entry.isDirectory()) {
          const chatSessionsDir = path.join(workspaceStorageRoot, entry.name, 'chatSessions');
          watchPaths.push(chatSessionsDir);
        }
      }
    } catch (error) {
      console.error(`[watcher] Failed to scan workspaceStorage:`, error);
    }
  } else if (sessionStateRoot) {
    // Fallback to legacy session-state
    const sessionDirs = await listSessionDirectories(sessionStateRoot);
    for (const sessionDir of sessionDirs) {
      const filePath = path.join(sessionDir, 'events.jsonl');
      const size = await getFileSize(filePath);
      if (size !== null) {
        cursors.set(filePath, { position: size, remainder: '' });
      }
    }
    watchPaths.push(sessionStateRoot);
  } else {
    console.warn('[watcher] No workspaceStorage or session-state root found.');
    return {
      close: async () => {
        // noop
      },
    };
  }

  const handleFullResync = async (filePath: string): Promise<void> => {
    const sessionId = extractSessionId(filePath);

    try {
      const events = await readSession(filePath);
      options.db.replaceSession(sessionId, events, {
        workspaceId: extractWorkspaceId(filePath),
      });

      const size = await getFileSize(filePath);
      if (size !== null) {
        cursors.set(filePath, { position: size, remainder: '' });
      }

      if (events.length > 0) {
        options.onEvents?.(sessionId, events);
      }
    } catch (error) {
      console.error(`[watcher] Failed to resync ${filePath}:`, error);
    }
  };

  const handleChange = async (filePath: string): Promise<void> => {
    const cursor = cursors.get(filePath);
    if (!cursor) {
      await handleFullResync(filePath);
      return;
    }

    try {
      const size = await getFileSize(filePath);
      if (size === null) {
        return;
      }

      if (size < cursor.position) {
        await handleFullResync(filePath);
        return;
      }

      if (size === cursor.position) {
        return;
      }

      const chunk = await readTextSlice(filePath, cursor.position);
      const combined = cursor.remainder + chunk.content;
      const lines = combined.split(/\r?\n/);
      const hasTrailingNewline = combined.endsWith('\n') || combined.endsWith('\r');
      const remainder = hasTrailingNewline ? '' : lines.pop() ?? '';
      const parsedEvents: JsonObject[] = [];

      for (const line of lines) {
        const event = parseEvent(line);
        if (event !== null) {
          parsedEvents.push(event);
        }
      }

      cursors.set(filePath, {
        position: chunk.size,
        remainder,
      });

      if (parsedEvents.length === 0) {
        return;
      }

      const sessionId = extractSessionId(filePath);
      options.db.appendEvents(sessionId, parsedEvents, {
        workspaceId: extractWorkspaceId(filePath),
      });
      options.onEvents?.(sessionId, parsedEvents);
    } catch (error) {
      console.error(`[watcher] Failed to process ${filePath}:`, error);
    }
  };

  const schedule = (filePath: string, task: () => Promise<void>) => {
    const pending = inFlight.get(filePath) ?? Promise.resolve();
    const next = pending
      .catch(() => undefined)
      .then(task)
      .finally(() => {
        if (inFlight.get(filePath) === next) {
          inFlight.delete(filePath);
        }
      });

    inFlight.set(filePath, next);
  };

  const watcher = chokidar.watch(watchPaths, {
    ignoreInitial: true,
    depth: workspaceStorageRoot ? 0 : 2, // workspaceStorage has chatSessions at depth 0, legacy has events.jsonl at depth 1
    awaitWriteFinish: {
      stabilityThreshold: 250,
      pollInterval: 100,
    },
  });

  watcher.on('add', (filePath) => {
    if (!isSessionFile(filePath)) {
      return;
    }

    schedule(filePath, () => handleFullResync(filePath));
  });

  watcher.on('change', (filePath) => {
    if (!isSessionFile(filePath)) {
      return;
    }

    schedule(filePath, () => handleChange(filePath));
  });

  watcher.on('unlink', (filePath) => {
    if (!isSessionFile(filePath)) {
      return;
    }

    cursors.delete(filePath);
    inFlight.delete(filePath);
  });

  watcher.on('error', (error) => {
    console.error('[watcher] Watcher error:', error);
  });

  await new Promise<void>((resolve) => {
    watcher.once('ready', () => resolve());
  });

  return {
    close: async () => {
      await watcher.close();
      await Promise.all([...inFlight.values()]);
    },
  };
}