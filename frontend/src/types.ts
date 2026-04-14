export interface SessionSummary {
  id: string;
  title: string | null;
  workspaceId: string | null;
  projectKey: string;
  projectName: string;
  projectPath: string | null;
  start: number | null;
  end: number | null;
  eventCount: number;
}

export interface StoredEvent {
  id: number;
  sessionId: string;
  type: string;
  timestamp: number | null;
  payload: unknown;
}

export interface NewEventsPayload {
  sessionId: string;
  events: StoredEvent[];
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
