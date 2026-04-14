import { promises as fs } from 'node:fs';
import path from 'node:path';
import websocket from '@fastify/websocket';
import Fastify, { type FastifyInstance } from 'fastify';
import type { ObserverDatabase } from './db';
import { eventBus } from './eventBus';
import { discoverSourcePaths, listChatSessionFiles } from './paths';
import type {
  SessionAgentStatus,
  SessionAgentSummary,
  StoredEventRow,
} from './types';

export interface ServerOptions {
  db: ObserverDatabase;
  enableWebsocket?: boolean;
  sessionStateRoot?: string | null;
  workspaceStorageRoot?: string | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && !Array.isArray(value) && typeof value === 'object';
}

function deserializePayload(payload: string): unknown {
  try {
    return JSON.parse(payload);
  } catch {
    return payload;
  }
}

function mapStoredEvent(row: StoredEventRow) {
  return {
    id: row.id,
    sessionId: row.sessionId,
    type: row.type,
    timestamp: row.timestamp,
    payload: deserializePayload(row.payload),
  };
}

function getAgentStatus(lastEventType: string): SessionAgentStatus {
  if (lastEventType === 'subagent.started') {
    return 'active';
  }

  if (lastEventType === 'subagent.selected') {
    return 'selected';
  }

  return 'completed';
}

function getStatusRank(status: SessionAgentStatus): number {
  switch (status) {
    case 'active':
      return 0;
    case 'selected':
      return 1;
    case 'completed':
      return 2;
  }
}

function extractSessionAgents(rows: StoredEventRow[]): SessionAgentSummary[] {
  const agentMap = new Map<
    string,
    SessionAgentSummary & {
      lastEventType: string;
    }
  >();

  for (const row of rows) {
    if (
      row.type !== 'subagent.selected' &&
      row.type !== 'subagent.started' &&
      row.type !== 'subagent.completed'
    ) {
      continue;
    }

    const payload = deserializePayload(row.payload);
    if (!isRecord(payload) || !isRecord(payload.data)) {
      continue;
    }

    const agentName = typeof payload.data.agentName === 'string' ? payload.data.agentName.trim() : '';
    if (!agentName) {
      continue;
    }

    const displayName =
      typeof payload.data.agentDisplayName === 'string' && payload.data.agentDisplayName.trim()
        ? payload.data.agentDisplayName.trim()
        : agentName;

    const current = agentMap.get(agentName) ?? {
      name: agentName,
      displayName,
      status: 'completed' as SessionAgentStatus,
      selectedCount: 0,
      startedCount: 0,
      completedCount: 0,
      lastSeen: null,
      lastEventType: row.type,
    };

    if (row.type === 'subagent.selected') {
      current.selectedCount += 1;
    } else if (row.type === 'subagent.started') {
      current.startedCount += 1;
    } else if (row.type === 'subagent.completed') {
      current.completedCount += 1;
    }

    current.displayName = displayName;
    current.lastSeen = row.timestamp;
    current.lastEventType = row.type;
    current.status = getAgentStatus(row.type);

    agentMap.set(agentName, current);
  }

  return [...agentMap.values()]
    .map(({ lastEventType: _lastEventType, ...agent }) => agent)
    .sort((left, right) => {
      const statusDelta = getStatusRank(left.status) - getStatusRank(right.status);
      if (statusDelta !== 0) {
        return statusDelta;
      }

      const leftSeen = left.lastSeen ?? 0;
      const rightSeen = right.lastSeen ?? 0;
      return rightSeen - leftSeen;
    });
}

async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function createApiServer(options: ServerOptions): Promise<FastifyInstance> {
  const app = Fastify({ logger: true });

  app.addHook('onRequest', async (request, reply) => {
    reply.header('Access-Control-Allow-Origin', '*');
    reply.header('Access-Control-Allow-Methods', 'GET,DELETE,OPTIONS');
    reply.header('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method === 'OPTIONS') {
      void reply.code(204).send();
    }
  });

  if (options.enableWebsocket !== false) {
    await app.register(websocket);

    app.get('/events/ws', { websocket: true }, (connection) => {
      const unsubscribe = eventBus.subscribe((payload) => {
        if (connection.socket.readyState !== 1) {
          return;
        }

        connection.socket.send(
          JSON.stringify({
            type: 'events.appended',
            sessionId: payload.sessionId,
            events: payload.events,
          }),
        );
      });

      connection.socket.on('close', unsubscribe);
      connection.socket.on('error', () => unsubscribe());
      connection.socket.send(JSON.stringify({ type: 'ready' }));
    });
  }

  app.get('/health', async () => ({ ok: true }));

  app.get('/sessions', async () => options.db.listSessions());

  app.get('/sessions/:id/events', async (request, reply) => {
    const params = request.params as { id: string };
    const session = options.db.getSession(params.id);

    if (!session) {
      reply.code(404);
      return {
        error: `Session ${params.id} not found`,
      };
    }

    return options.db.listSessionEvents(params.id).map(mapStoredEvent);
  });

  app.get('/sessions/:id/agents', async (request, reply) => {
    const params = request.params as { id: string };
    const session = options.db.getSession(params.id);

    if (!session) {
      reply.code(404);
      return {
        error: `Session ${params.id} not found`,
      };
    }

    return extractSessionAgents(options.db.listSessionEvents(params.id));
  });

  app.delete('/sessions/:id', async (request, reply) => {
    const params = request.params as { id: string };
    const session = options.db.getSession(params.id);

    if (!session) {
      reply.code(404);
      return {
        error: `Session ${params.id} not found`,
      };
    }

    let deletedFromDisk = false;
    let deletedPath: string | null = null;

    // Try workspaceStorage first (new format)
    const discovered = await discoverSourcePaths();
    const workspaceStorageRoot = options.workspaceStorageRoot ?? discovered.workspaceStorageRoot;
    if (workspaceStorageRoot) {
      const sessionFiles = await listChatSessionFiles(workspaceStorageRoot);
      const sessionFile = sessionFiles.find((f) => f.sessionId === params.id);
      if (sessionFile) {
        deletedPath = sessionFile.filePath;
        try {
          await fs.unlink(sessionFile.filePath);
          deletedFromDisk = true;
        } catch (error) {
          request.log.error(error, `Failed to remove session file ${sessionFile.filePath}`);
        }
      }
    }

    // Fallback to session-state (legacy format)
    if (!deletedFromDisk && options.sessionStateRoot) {
      const candidatePath = path.join(options.sessionStateRoot, params.id);
      deletedPath = candidatePath;

      if (await pathExists(candidatePath)) {
        try {
          await fs.rm(candidatePath, { recursive: true, force: true });
          deletedFromDisk = true;
        } catch (error) {
          request.log.error(error, `Failed to remove session directory ${candidatePath}`);
        }
      }
    }

    const deleted = options.db.deleteSession(params.id);
    return {
      deleted,
      deletedFromDisk,
      deletedPath,
    };
  });

  return app;
}