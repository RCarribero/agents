import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

async function pathExists(targetPath) {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function findSessionDirectories(sessionStateRoot) {
  if (!(await pathExists(sessionStateRoot))) {
    return [];
  }

  const entries = await fs.readdir(sessionStateRoot, { withFileTypes: true });
  const sessions = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const sessionPath = path.join(sessionStateRoot, entry.name);
    const eventsPath = path.join(sessionPath, 'events.jsonl');
    if (await pathExists(eventsPath)) {
      sessions.push(sessionPath);
    }
  }

  sessions.sort();
  return sessions;
}

async function findCopilotChatRoots() {
  const appDataRoot = process.env.APPDATA ?? path.join(os.homedir(), 'AppData', 'Roaming');
  const workspaceStorageRoot = path.join(appDataRoot, 'Code - Insiders', 'User', 'workspaceStorage');

  if (!(await pathExists(workspaceStorageRoot))) {
    return { workspaceStorageRoot, roots: [] };
  }

  const entries = await fs.readdir(workspaceStorageRoot, { withFileTypes: true });
  const roots = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }

    const candidate = path.join(workspaceStorageRoot, entry.name, 'GitHub.copilot-chat');
    if (await pathExists(candidate)) {
      roots.push(candidate);
    }
  }

  roots.sort();
  return { workspaceStorageRoot, roots };
}

function parseLine(line) {
  const trimmed = line.trim();
  if (!trimmed) {
    return null;
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
      return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

async function main() {
  const sessionStateRoot = path.join(os.homedir(), '.copilot', 'session-state');
  const hasSessionStateRoot = await pathExists(sessionStateRoot);
  const { workspaceStorageRoot, roots: copilotChatRoots } = await findCopilotChatRoots();
  const hasWorkspaceStorageRoot = await pathExists(workspaceStorageRoot);
  const sessionDirs = await findSessionDirectories(sessionStateRoot);

  console.log('Session-state root:', hasSessionStateRoot ? sessionStateRoot : 'missing');
  console.log(
    'Copilot Chat workspaceStorage root:',
    hasWorkspaceStorageRoot ? workspaceStorageRoot : 'missing',
  );

  if (copilotChatRoots.length === 0) {
    console.log('Copilot Chat folders: none found');
  } else {
    console.log('Copilot Chat folders:');
    for (const root of copilotChatRoots.slice(0, 5)) {
      console.log(`- ${root}`);
    }
  }

  if (sessionDirs.length === 0) {
    console.log('No session folders with events.jsonl were found.');
    return;
  }

  const sessionPath = sessionDirs[0];
  const eventsPath = path.join(sessionPath, 'events.jsonl');

  let rawContent = '';
  try {
    rawContent = await fs.readFile(eventsPath, 'utf8');
  } catch (error) {
    console.error(`[recon] Could not read ${eventsPath}:`, error);
    return;
  }

  const rawLines = rawContent.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const eventTypes = new Set();

  for (const line of rawLines) {
    const parsed = parseLine(line);
    if (parsed && typeof parsed.type === 'string') {
      eventTypes.add(parsed.type);
    }
  }

  console.log(`Session picked: ${sessionPath}`);
  console.log('Event types:');
  if (eventTypes.size === 0) {
    console.log('- none parsed');
  } else {
    for (const type of [...eventTypes].sort()) {
      console.log(`- ${type}`);
    }
  }

  console.log('Sample lines:');
  for (const line of rawLines.slice(0, 5)) {
    console.log(line);
  }
}

main().catch((error) => {
  console.error('[recon] Failed:', error);
  process.exitCode = 1;
});