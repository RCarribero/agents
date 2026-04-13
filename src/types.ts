export type JsonObject = Record<string, unknown>;

export interface SessionSummary {
  id: string;
  start: number | null;
  end: number | null;
  eventCount: number;
}

export interface StoredEventRow {
  id: number;
  sessionId: string;
  type: string;
  timestamp: number | null;
  payload: string;
}

export type SessionAgentStatus = 'active' | 'selected' | 'completed';

export interface SessionAgentSummary {
  name: string;
  displayName: string;
  status: SessionAgentStatus;
  selectedCount: number;
  startedCount: number;
  completedCount: number;
  lastSeen: number | null;
}

export interface NewEventsPayload {
  sessionId: string;
  events: JsonObject[];
}