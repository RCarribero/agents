import type { JsonObject } from './types';

export function isJsonObject(value: unknown): value is JsonObject {
  return value !== null && !Array.isArray(value) && typeof value === 'object';
}

export function getEventType(event: JsonObject): string {
  const directType = typeof event.type === 'string' ? event.type.trim() : '';
  if (directType) {
    return directType;
  }

  if (isJsonObject(event.data)) {
    const nestedType = typeof event.data.type === 'string' ? event.data.type.trim() : '';
    if (nestedType) {
      return nestedType;
    }
  }

  return 'unknown';
}

function parseTimestampValue(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }

  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (/^\d+(\.\d+)?$/.test(trimmed)) {
    const numeric = Number(trimmed);
    return Number.isFinite(numeric) ? Math.trunc(numeric) : null;
  }

  const parsed = Date.parse(trimmed);
  return Number.isNaN(parsed) ? null : parsed;
}

export function getEventTimestamp(event: JsonObject): number | null {
  const topLevelTimestamp = parseTimestampValue(event.timestamp);
  if (topLevelTimestamp !== null) {
    return topLevelTimestamp;
  }

  if (!isJsonObject(event.data)) {
    return null;
  }

  const nestedKeys = ['timestamp', 'startTime', 'endTime', 'createdAt', 'updatedAt'];
  for (const key of nestedKeys) {
    const nestedTimestamp = parseTimestampValue(event.data[key]);
    if (nestedTimestamp !== null) {
      return nestedTimestamp;
    }
  }

  return null;
}

export function serializeEvent(event: JsonObject): string {
  try {
    return JSON.stringify(event);
  } catch {
    return '{}';
  }
}

export function mergeBounds(
  current: { start: number | null; end: number | null } | undefined,
  events: JsonObject[],
): { start: number | null; end: number | null } {
  let nextStart = current?.start ?? null;
  let nextEnd = current?.end ?? null;

  for (const event of events) {
    const timestamp = getEventTimestamp(event);
    if (timestamp === null) {
      continue;
    }

    nextStart = nextStart === null ? timestamp : Math.min(nextStart, timestamp);
    nextEnd = nextEnd === null ? timestamp : Math.max(nextEnd, timestamp);
  }

  return {
    start: nextStart,
    end: nextEnd,
  };
}