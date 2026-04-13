import type { FastifyInstance } from 'fastify';
import { createObserverDatabase } from './db';
import { eventBus } from './eventBus';
import { discoverSourcePaths } from './paths';
import { createApiServer } from './server';
import { scanSessions } from './scanSessions';
import { startSessionWatcher, type SessionWatcher } from './watcher';

function getPort(rawPort: string | undefined): number {
  const parsedPort = Number(rawPort);
  return Number.isInteger(parsedPort) && parsedPort > 0 ? parsedPort : 3010;
}

async function main(): Promise<void> {
  const db = createObserverDatabase();
  let server: FastifyInstance | null = null;
  let watcher: SessionWatcher | null = null;
  let shuttingDown = false;

  const shutdown = async (signal: string): Promise<void> => {
    if (shuttingDown) {
      return;
    }

    shuttingDown = true;
    console.log(`[observer] ${signal} received, shutting down.`);

    if (watcher) {
      await watcher.close();
    }

    if (server) {
      await server.close();
    }

    db.close();
  };

  try {
    const sources = await discoverSourcePaths();
    console.log(`[observer] session-state root: ${sources.sessionStateRoot ?? 'not found'}`);
    console.log(`[observer] copilot-chat roots: ${sources.copilotChatRoots.length}`);

    const scanResult = await scanSessions({ db, sessionStateRoot: sources.sessionStateRoot });
    console.log(
      `[observer] initial scan: ${scanResult.scannedSessions} sessions, ${scanResult.loadedEvents} events, ${scanResult.errors} errors`,
    );
    console.log(`[observer] database: ${db.path}`);

    if (sources.sessionStateRoot) {
      watcher = await startSessionWatcher({
        db,
        sessionStateRoot: sources.sessionStateRoot,
        onEvents: (sessionId, events) => {
          eventBus.emitNewEvents({ sessionId, events });
          console.log(`[watcher] ${sessionId}: ${events.length} new event(s)`);
        },
      });

      console.log('[observer] watcher enabled.');
    } else {
      console.warn('[observer] watcher disabled because no session-state root was found.');
    }

    server = await createApiServer({
      db,
      enableWebsocket: true,
      sessionStateRoot: sources.sessionStateRoot,
    });
    const host = process.env.HOST ?? '127.0.0.1';
    const port = getPort(process.env.PORT);
    const address = await server.listen({ host, port });
    console.log(`[observer] API ready at ${address}`);

    process.on('SIGINT', () => {
      void shutdown('SIGINT').finally(() => process.exit(0));
    });

    process.on('SIGTERM', () => {
      void shutdown('SIGTERM').finally(() => process.exit(0));
    });
  } catch (error) {
    console.error('[observer] Fatal error:', error);
    await shutdown('FATAL');
    process.exitCode = 1;
  }
}

void main();