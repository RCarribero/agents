import { promises as fs } from 'node:fs';
import path from 'node:path';
import { getEventTimestamp } from './eventUtils';
import { parseEvent } from './parser';
import type { JsonObject } from './types';

interface IndexedEvent {
  index: number;
  timestamp: number | null;
  event: JsonObject;
}

async function getSessionFilePath(input: string): Promise<string | null> {
  // If input is a direct .jsonl file, use it
  if (input.endsWith('.jsonl')) {
    const exists = await pathExists(input);
    if (exists) {
      return input;
    }
    return null;
  }

  // If input is a directory, look for events.jsonl inside (legacy format)
  const eventsPath = path.join(input, 'events.jsonl');
  const exists = await pathExists(eventsPath);
  if (exists) {
    return eventsPath;
  }

  return null;
}

async function pathExists(targetPath: string): Promise<boolean> {
  try {
    await fs.access(targetPath);
    return true;
  } catch {
    return false;
  }
}

export async function readSession(sessionPathOrFile: string): Promise<JsonObject[]> {
  const eventsPath = await getSessionFilePath(sessionPathOrFile);

  if (!eventsPath) {
    console.error(`[readSession] No events file found for ${sessionPathOrFile}`);
    return [];
  }

  let rawContent = '';
  try {
    rawContent = await fs.readFile(eventsPath, 'utf8');
  } catch (error) {
    console.error(`[readSession] Failed to read ${eventsPath}:`, error);
    return [];
  }

  const events: IndexedEvent[] = [];
  const lines = rawContent.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const event = parseEvent(lines[index] ?? '');
    if (event === null) {
      continue;
    }

    events.push({
      index,
      timestamp: getEventTimestamp(event),
      event,
    });
  }

  events.sort((left, right) => {
    if (left.timestamp === null || right.timestamp === null) {
      return left.index - right.index;
    }

    if (left.timestamp === right.timestamp) {
      return left.index - right.index;
    }

    return left.timestamp - right.timestamp;
  });

  return events.map((entry) => entry.event);
}