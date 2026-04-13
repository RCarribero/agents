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

export async function readSession(sessionPath: string): Promise<JsonObject[]> {
  const eventsPath = path.join(sessionPath, 'events.jsonl');

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