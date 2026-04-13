# Copilot Observer Frontend

Astro + Tailwind + TypeScript dashboard for viewing Copilot session events.

## Structure

```
frontend/
├── src/
│   ├── components/          # Reusable Astro components
│   │   ├── SessionCard.astro
│   │   ├── EventCard.astro
│   │   └── SessionsList.astro
│   ├── layouts/             # Shared page layouts
│   │   └── BaseLayout.astro
│   ├── lib/                 # Client utilities
│   │   └── observerClient.ts
│   ├── pages/               # Routes (Astro file-based routing)
│   │   ├── index.astro      # Sessions list
│   │   └── sessions/[id].astro    # Session details
│   └── types.ts             # Shared TypeScript interfaces
├── astro.config.mjs         # Astro configuration with Tailwind integration
├── tsconfig.json            # TypeScript configuration
├── tailwind.config.mjs       # Tailwind CSS configuration
├── postcss.config.mjs        # PostCSS configuration
└── package.json             # Dependencies
```

## Development

### Start the backend (if not already running)

```bash
cd ..  # Go to root (.copilot)
npm start
```

Backend will listen on `http://127.0.0.1:3010`.

### Start the frontend dev server

```bash
npm run dev
```

Frontend will be available at `http://127.0.0.1:3011`.

### Build for production

```bash
npm run build
npm run preview  # Preview the built site locally
```

## Features

### Pages

- **`/`** — Sessions list
  - Shows all sessions with event counts and timestamps
  - Click a session to view its events
  - Auto-refreshes every 5 seconds
  
- **`/sessions/[id]`** — Session details
  - Shows full session metadata
  - Displays events grouped by type
  - Click "Show payload" on any event to inspect full JSON

### Components

- **`SessionCard.astro`** — Individual session display
- **`EventCard.astro`** — Individual event display with collapsible payload
- **`SessionsList.astro`** — Auto-refreshing session list with auto-fetch every 5s

### Utilities

- **`observerClient.ts`** — Client library for backend API
  - `getSessions()` — Fetch all sessions
  - `getSessionEvents(sessionId)` — Fetch events for a session
  - `connectWebSocket()` — Subscribe to real-time events

## Backend API

The frontend expects the backend API at `http://127.0.0.1:3010`:

- `GET /health` — Health check
- `GET /sessions` — List all sessions
- `GET /sessions/:id/events` — Get events for a session
- `GET /events/ws` — WebSocket for real-time events

## Environment Variables

Currently hardcoded to `http://127.0.0.1:3010`. To change:

1. Edit `frontend/src/lib/observerClient.ts` and change the `backendUrl` parameter
2. Update `src/pages/*.astro` fetch URLs manually
3. Or create a `.env.local` file with:
   ```
   PUBLIC_BACKEND_URL=http://your-backend-url:3010
   ```
   Then import and use `import.meta.env.PUBLIC_BACKEND_URL` in pages

## Browser Compatibility

- Modern browsers with ES2022 support
- WebSocket support (for real-time events)
- LocalStorage not required (stateless frontend)

## Troubleshooting

### Connection error: "Failed to connect to backend"

Make sure the backend is running:
```bash
# In the root .copilot directory
npm start
```

### Build errors

Clear Astro cache and reinstall:
```bash
rm -r node_modules dist .astro
npm install
npm run build
```
