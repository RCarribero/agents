# Copilot Observer

Local backend + frontend dashboard for reading, parsing, and visualizing Copilot session event data.

## Quick Start

### Prerequisites

- Node.js 16+ 
- npm

### Backend Setup

```bash
# Install backend dependencies
npm install

# Initial scan of all Copilot sessions
npm run scan

# Start backend server (listening on 127.0.0.1:3010)
npm start
```

The backend will:
1. Discover Copilot session directories from `~/.copilot/session-state/` and `%APPDATA%\Code - Insiders\...`
2. Parse JSONL event files
3. Store events in SQLite (`observer.db`)
4. Start Fastify API on `127.0.0.1:3010`
5. Watch for incremental changes and update the database

### Frontend Setup

```bash
cd frontend

# Install frontend dependencies (already done)
npm install

# Start dev server (listening on 127.0.0.1:3011)
npm run dev
```

Open `http://127.0.0.1:3011` in your browser to view the dashboard.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Copilot Observer                          │
├──────────────────────────┬──────────────────────────────────┤
│                          │                                   │
│  Backend (Node.ts)       │    Frontend (Astro+Tailwind)     │
│  ─────────────────       │    ────────────────────────────  │
│  • Path discovery        │    • Sessions list (/)            │
│  • JSONL parser          │    • Session details (/sessions..)│
│  • SQLite persistence    │    • Auto-refresh (5s interval)   │
│  • File watcher          │    • Event visualization         │
│  • Fastify API           │    • WebSocket real-time         │
│  • EventBus              │    • Tailwind styling            │
│  (Port 3010)             │    (Port 3011)                   │
│                          │                                   │
└──────────────────────────┴──────────────────────────────────┘
                           ↓
                    ┌──────────────┐
                    │ observer.db  │
                    │  (SQLite)    │
                    └──────────────┘
                           ↑
         Watches for changes in session-state/*/events.jsonl
```

## Backend API

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check → `{ ok: true }` |
| GET | `/sessions` | List all sessions with event counts |
| GET | `/sessions/:id/events` | Get all events for a session |
| GET | `/events/ws` | WebSocket for real-time events |

### Response Format

**GET /sessions**
```json
[
  {
    "id": "session-uuid",
    "start": 1704067200000,
    "end": 1704067500000,
    "eventCount": 42
  }
]
```

**GET /sessions/:id/events**
```json
[
  {
    "id": 1,
    "sessionId": "session-uuid",
    "type": "message.submitted",
    "timestamp": 1704067200000,
    "payload": { ... }
  }
]
```

**WebSocket /events/ws**

Broadcasts new events as they're detected:
```json
{
  "type": "events.appended",
  "sessionId": "session-uuid",
  "events": [ ... ]
}
```

## Frontend Features

- **Sessions List** (`/`)
  - Shows all available sessions
  - Event count and timestamps
  - Auto-refresh every 5 seconds
  - Direct links to session details

- **Session Details** (`/sessions/:id`)
  - Session metadata (ID, start time, event count)
  - Events grouped by type
  - Collapsible event payloads (JSON)
  - Total event statistics

- **Real-Time Updates** (via WebSocket)
  - Live event streaming when new events are appended
  - Auto-updates session list

## File Structure

```
.
├── backend code (src/)
│   ├── index.ts              # Server startup & orchestration
│   ├── server.ts             # Fastify API definition
│   ├── parser.ts             # JSONL event parsing
│   ├── readSession.ts        # Single session ingestion
│   ├── db.ts                 # SQLite schema & operations
│   ├── watcher.ts            # File-watching & incremental update
│   ├── eventBus.ts           # Real-time event emission
│   ├── eventUtils.ts         # Event introspection utilities
│   ├── paths.ts              # Path discovery
│   └── scanSessions.ts       # Batch scan
│
├── frontend/ (Astro project)
│   ├── src/
│   │   ├── pages/
│   │   │   ├── index.astro                   # / route
│   │   │   └── sessions/[id].astro          # /sessions/:id route
│   │   ├── components/
│   │   │   ├── SessionCard.astro
│   │   │   ├── EventCard.astro
│   │   │   └── SessionsList.astro
│   │   ├── layouts/
│   │   │   └── BaseLayout.astro
│   │   ├── lib/
│   │   │   └── observerClient.ts            # Backend client
│   │   └── types.ts                         # Shared interfaces
│   ├── astro.config.mjs
│   ├── tsconfig.json
│   └── tailwind.config.mjs
│
├── package.json              # Backend dependencies
├── tsconfig.json             # Backend TypeScript config
├── observer.db               # SQLite database (created on first run)
└── recon.mjs                 # Session discovery exploration script
```

## Data Flow

1. **Startup**
   - Backend discovers session directories
   - Reads all `events.jsonl` files
   - Parses and stores in SQLite
   - Starts API server

2. **Incremental Updates**
   - Watcher monitors `session-state/*/events.jsonl`
   - On file change, reads only new bytes
   - Parses new events
   - Inserts into database
   - Broadcasts via WebSocket

3. **Frontend Access**
   - Fetches sessions from `GET /sessions`
   - Fetches events for selected session via `GET /sessions/:id/events`
   - Subscribes to `GET /events/ws` for real-time updates
   - Auto-refreshes session list every 5 seconds

## Troubleshooting

### Backend won't start

**Error:** `Cannot find sessions directory`
- Check that `~/.copilot/session-state/` exists
- Or check `%APPDATA%\Code - Insiders\User\workspaceStorage\...`
- Run `node recon.mjs` to verify directories

**Error:** `Address already in use`
- Port 3010 is already in use
- Kill existing process: `lsof -ti:3010 | xargs kill -9` (macOS/Linux) or `netstat -ano | findstr :3010` (Windows)
- Or change port in `src/server.ts`

### Frontend can't connect

**Error:** `Failed to connect to backend`
- Make sure backend is running on `http://127.0.0.1:3010`
- Check browser DevTools Network tab for failed requests
- Verify no CORS issues (backend allows all origins)

### No events showing

- Run `npm run scan` to load initial data
- Check `observer.db` exists
- Run `sqlite3 observer.db "SELECT COUNT(*) FROM events"` to verify
- Check backend logs for parsing errors

## Development

### Add a new backend endpoint

Edit `src/server.ts`:
```typescript
app.get('/new-endpoint', async (request, reply) => {
  return { data: 'response' };
});
```

### Add a new frontend page

Create a file in `frontend/src/pages/`:
```astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
---

<BaseLayout title="New Page">
  <h1>Content here</h1>
</BaseLayout>
```

### Connect to WebSocket in frontend

Use `observerClient.ts`:
```typescript
const client = new ObserverClient();
const unsubscribe = client.connectWebSocket(
  (payload) => console.log('New events:', payload),
  (error) => console.error('WS error:', error)
);
// Later: unsubscribe();
```

## Performance

- **Database:** WAL mode for concurrent read/write
- **Watcher:** Only reads new bytes from changed files (cursor tracking)
- **API:** Endpoint responses are fast; events deserialized on-demand
- **Frontend:** Static site generation at build time; minimal JavaScript

## Roadmap

- [ ] Export events to CSV/JSON
- [ ] Event filtering by type/date range
- [ ] Session comparison view
- [ ] WebSocket real-time event ticker
- [ ] Configurable backend port
- [ ] Environment variables for paths

## License

Internal use. See [LICENSE](LICENSE).
