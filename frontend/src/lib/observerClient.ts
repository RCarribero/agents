import type { NewEventsPayload, SessionAgentSummary, SessionSummary, SessionStats, StoredEvent } from '../types';

export class ObserverClient {
  private backendUrl: string;

  constructor(backendUrl: string = 'http://127.0.0.1:3010') {
    this.backendUrl = backendUrl;
  }

  async getSessions() {
    const res = await fetch(`${this.backendUrl}/sessions`);
    if (!res.ok) throw new Error(`Failed to fetch sessions: ${res.statusText}`);
    return res.json() as Promise<SessionSummary[]>;
  }

  async getSessionEvents(sessionId: string) {
    const res = await fetch(`${this.backendUrl}/sessions/${sessionId}/events`);
    if (!res.ok) throw new Error(`Failed to fetch events: ${res.statusText}`);
    return res.json() as Promise<StoredEvent[]>;
  }

  async getSessionAgents(sessionId: string) {
    const res = await fetch(`${this.backendUrl}/sessions/${sessionId}/agents`);
    if (!res.ok) throw new Error(`Failed to fetch agents: ${res.statusText}`);
    return res.json() as Promise<SessionAgentSummary[]>;
  }

  async getSessionStats(sessionId: string) {
    const res = await fetch(`${this.backendUrl}/sessions/${sessionId}/stats`);
    if (!res.ok) throw new Error(`Failed to fetch session stats: ${res.statusText}`);
    return res.json() as Promise<SessionStats>;
  }

  async deleteSession(sessionId: string) {
    const res = await fetch(`${this.backendUrl}/sessions/${sessionId}`, {
      method: 'DELETE',
    });
    if (!res.ok) throw new Error(`Failed to delete session: ${res.statusText}`);
    return res.json() as Promise<{ deleted: boolean; deletedFromDisk: boolean; deletedPath: string | null }>;
  }

  connectWebSocket(
    onMessage: (payload: NewEventsPayload) => void,
    onError: (error: Error) => void = () => {},
  ): () => void {
    const wsUrl = `ws://${this.backendUrl.split('://')[1]}/events/ws`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      console.log('[observer] WebSocket connected');
    };

    ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        if (message.type === 'events.appended') {
          onMessage(message);
        }
      } catch (error) {
        console.error('[observer] Failed to parse WebSocket message:', error);
      }
    };

    ws.onerror = (event) => {
      const error = new Error('WebSocket error');
      console.error('[observer] WebSocket error:', error);
      onError(error);
    };

    ws.onclose = () => {
      console.log('[observer] WebSocket disconnected');
    };

    return () => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    };
  }
}
