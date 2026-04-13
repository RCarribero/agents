import type { JsonObject } from './types';

export function parseEvent(line: string): JsonObject | null {
  const trimmed = line.trim();
  if (!trimmed) {
    return null;
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
      return null;
    }

    return parsed as JsonObject;
  } catch {
    return null;
  }
}