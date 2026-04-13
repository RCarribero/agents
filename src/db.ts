import Database from 'better-sqlite3';
import path from 'node:path';
import { getEventTimestamp, getEventType, mergeBounds, serializeEvent } from './eventUtils';
import type { JsonObject, SessionSummary, StoredEventRow } from './types';

type SessionBounds = {
  start: number | null;
  end: number | null;
};

export interface ObserverDatabase {
  readonly path: string;
  replaceSession(sessionId: string, events: JsonObject[]): void;
  appendEvents(sessionId: string, events: JsonObject[]): void;
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

  const upsertSession = db.prepare(`
INSERT INTO sessions (id, start, end)
VALUES (@id, @start, @end)
ON CONFLICT(id) DO UPDATE SET
  start = excluded.start,
  end = excluded.end
`);

  const selectSession = db.prepare(`
SELECT s.id AS id, s.start AS start, s.end AS end, COUNT(e.id) AS eventCount
FROM sessions s
LEFT JOIN events e ON e.session_id = s.id
WHERE s.id = ?
GROUP BY s.id, s.start, s.end
`);

  const selectSessionBounds = db.prepare(`SELECT start, end FROM sessions WHERE id = ?`);

  const selectSessions = db.prepare(`
SELECT s.id AS id, s.start AS start, s.end AS end, COUNT(e.id) AS eventCount
FROM sessions s
LEFT JOIN events e ON e.session_id = s.id
GROUP BY s.id, s.start, s.end
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

  const replaceSession = db.transaction((sessionId: string, events: JsonObject[]) => {
    deleteSessionEvents.run(sessionId);

    const bounds = mergeBounds(undefined, events);
    upsertSession.run({
      id: sessionId,
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

  const appendEvents = db.transaction((sessionId: string, events: JsonObject[]) => {
    const currentBounds = selectSessionBounds.get(sessionId) as SessionBounds | undefined;
    const nextBounds = mergeBounds(currentBounds, events);

    upsertSession.run({
      id: sessionId,
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