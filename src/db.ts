import Database from 'better-sqlite3';
import path from 'node:path';
import {
  getEventTimestamp,
  getEventType,
  mergeBounds,
  mergeSessionTitle,
  serializeEvent,
} from './eventUtils';
import { mergeSessionProjectInfo, type SessionProjectState } from './sessionProject';
import type { JsonObject, SessionSummary, StoredEventRow } from './types';

export interface SessionIngestMetadata {
  workspaceId?: string | null;
}

type PersistedSessionState = SessionProjectState & {
  title: string | null;
  start: number | null;
  end: number | null;
};

export interface ObserverDatabase {
  readonly path: string;
  replaceSession(sessionId: string, events: JsonObject[], metadata?: SessionIngestMetadata): void;
  appendEvents(sessionId: string, events: JsonObject[], metadata?: SessionIngestMetadata): void;
  deleteSession(sessionId: string): boolean;
  listSessions(): SessionSummary[];
  getSession(sessionId: string): SessionSummary | undefined;
  listSessionEvents(sessionId: string): StoredEventRow[];
  countEvents(): number;
  close(): void;
}

export function createObserverDatabase(
  dbPath = path.resolve(process.cwd(), 'observer.db'),
): ObserverDatabase {
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');

  db.exec(`
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  title TEXT,
  workspace_id TEXT,
  project_key TEXT,
  project_name TEXT,
  project_path TEXT,
  start INTEGER,
  end INTEGER
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  type TEXT,
  timestamp INTEGER,
  payload TEXT
);

CREATE INDEX IF NOT EXISTS idx_events_session_id ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_session_timestamp ON events(session_id, timestamp, id);
`);

  const sessionColumns = db.prepare(`PRAGMA table_info(sessions)`).all() as Array<{ name: string }>;
  const ensureSessionColumn = (columnName: string, definition: string) => {
    if (!sessionColumns.some((column) => column.name === columnName)) {
      db.exec(`ALTER TABLE sessions ADD COLUMN ${columnName} ${definition}`);
    }
  };

  ensureSessionColumn('title', 'TEXT');
  ensureSessionColumn('workspace_id', 'TEXT');
  ensureSessionColumn('project_key', 'TEXT');
  ensureSessionColumn('project_name', 'TEXT');
  ensureSessionColumn('project_path', 'TEXT');

  const upsertSession = db.prepare(`
INSERT INTO sessions (id, title, workspace_id, project_key, project_name, project_path, start, end)
VALUES (@id, @title, @workspaceId, @projectKey, @projectName, @projectPath, @start, @end)
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  workspace_id = excluded.workspace_id,
  project_key = excluded.project_key,
  project_name = excluded.project_name,
  project_path = excluded.project_path,
  start = excluded.start,
  end = excluded.end
`);

  const selectSession = db.prepare(`
SELECT s.id AS id,
       s.title AS title,
       s.workspace_id AS workspaceId,
       COALESCE(s.project_key, 'unknown') AS projectKey,
       COALESCE(s.project_name, 'Sin proyecto detectado') AS projectName,
       s.project_path AS projectPath,
       s.start AS start,
       s.end AS end,
       COUNT(e.id) AS eventCount
FROM sessions s
LEFT JOIN events e ON e.session_id = s.id
WHERE s.id = ?
GROUP BY s.id, s.title, s.workspace_id, s.project_key, s.project_name, s.project_path, s.start, s.end
`);

  const selectSessionState = db.prepare(`
SELECT title,
       workspace_id AS workspaceId,
       COALESCE(project_key, 'unknown') AS projectKey,
       project_name AS projectName,
       project_path AS projectPath,
       start,
       end
FROM sessions
WHERE id = ?
`);

  const selectSessions = db.prepare(`
SELECT s.id AS id,
       s.title AS title,
       s.workspace_id AS workspaceId,
       COALESCE(s.project_key, 'unknown') AS projectKey,
       COALESCE(s.project_name, 'Sin proyecto detectado') AS projectName,
       s.project_path AS projectPath,
       s.start AS start,
       s.end AS end,
       COUNT(e.id) AS eventCount
FROM sessions s
LEFT JOIN events e ON e.session_id = s.id
GROUP BY s.id, s.title, s.workspace_id, s.project_key, s.project_name, s.project_path, s.start, s.end
ORDER BY COALESCE(s.end, s.start, 0) DESC, s.id DESC
`);

  const selectSessionEvents = db.prepare(`
SELECT id, session_id AS sessionId, type, timestamp, payload
FROM events
WHERE session_id = ?
ORDER BY CASE WHEN timestamp IS NULL THEN 1 ELSE 0 END, timestamp ASC, id ASC
`);

  const deleteSessionEvents = db.prepare(`DELETE FROM events WHERE session_id = ?`);
  const deleteSessionStatement = db.prepare(`DELETE FROM sessions WHERE id = ?`);

  const insertEvent = db.prepare(`
INSERT INTO events (session_id, type, timestamp, payload)
VALUES (@sessionId, @type, @timestamp, @payload)
`);

  const countEventsStatement = db.prepare(`SELECT COUNT(*) AS total FROM events`);

  const replaceSession = db.transaction((
    sessionId: string,
    events: JsonObject[],
    metadata?: SessionIngestMetadata,
  ) => {
    const legacySessionId = sessionId.endsWith('.') ? sessionId : `${sessionId}.`;

    if (legacySessionId !== sessionId) {
      deleteSessionEvents.run(legacySessionId);
      deleteSessionStatement.run(legacySessionId);
    }

    deleteSessionEvents.run(sessionId);
    deleteSessionStatement.run(sessionId);

    const bounds = mergeBounds(undefined, events);
    const title = mergeSessionTitle(undefined, events);
    const project = mergeSessionProjectInfo(undefined, events, metadata?.workspaceId);
    upsertSession.run({
      id: sessionId,
      title,
      workspaceId: project.workspaceId,
      projectKey: project.projectKey,
      projectName: project.projectName,
      projectPath: project.projectPath,
      start: bounds.start,
      end: bounds.end,
    });

    for (const event of events) {
      insertEvent.run({
        sessionId,
        type: getEventType(event),
        timestamp: getEventTimestamp(event),
        payload: serializeEvent(event),
      });
    }
  });

  const appendEvents = db.transaction((
    sessionId: string,
    events: JsonObject[],
    metadata?: SessionIngestMetadata,
  ) => {
    const currentState = selectSessionState.get(sessionId) as PersistedSessionState | undefined;
    const currentBounds = currentState
      ? { start: currentState.start, end: currentState.end }
      : undefined;
    const nextBounds = mergeBounds(currentBounds, events);
    const nextTitle = mergeSessionTitle(currentState?.title, events);
    const nextProject = mergeSessionProjectInfo(currentState, events, metadata?.workspaceId);

    upsertSession.run({
      id: sessionId,
      title: nextTitle,
      workspaceId: nextProject.workspaceId,
      projectKey: nextProject.projectKey,
      projectName: nextProject.projectName,
      projectPath: nextProject.projectPath,
      start: nextBounds.start,
      end: nextBounds.end,
    });

    for (const event of events) {
      insertEvent.run({
        sessionId,
        type: getEventType(event),
        timestamp: getEventTimestamp(event),
        payload: serializeEvent(event),
      });
    }
  });

  const deleteSession = db.transaction((sessionId: string) => {
    deleteSessionEvents.run(sessionId);
    const result = deleteSessionStatement.run(sessionId);
    return result.changes > 0;
  });

  return {
    path: dbPath,
    replaceSession,
    appendEvents,
    deleteSession,
    listSessions: () => selectSessions.all() as SessionSummary[],
    getSession: (sessionId: string) => selectSession.get(sessionId) as SessionSummary | undefined,
    listSessionEvents: (sessionId: string) => selectSessionEvents.all(sessionId) as StoredEventRow[],
    countEvents: () => (countEventsStatement.get() as { total: number }).total,
    close: () => db.close(),
  };
}