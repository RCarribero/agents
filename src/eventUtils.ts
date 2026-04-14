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

function parseTimestampFromRecord(record: JsonObject): number | null {
  const candidateKeys = ['timestamp', 'startTime', 'endTime', 'createdAt', 'updatedAt', 'creationDate'];

  for (const key of candidateKeys) {
    const parsed = parseTimestampValue(record[key]);
    if (parsed !== null) {
      return parsed;
    }
  }

  return null;
}

function parseTimestampFromUnknown(value: unknown): number | null {
  if (isJsonObject(value)) {
    const directTimestamp = parseTimestampFromRecord(value);
    if (directTimestamp !== null) {
      return directTimestamp;
    }

    if (isJsonObject(value.data)) {
      const nestedDataTimestamp = parseTimestampFromRecord(value.data);
      if (nestedDataTimestamp !== null) {
        return nestedDataTimestamp;
      }
    }
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const nestedTimestamp = parseTimestampFromUnknown(item);
      if (nestedTimestamp !== null) {
        return nestedTimestamp;
      }
    }
  }

  return null;
}

function parseTitleValue(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

export function getSessionTitle(event: JsonObject): string | null {
  const directTitle = parseTitleValue(event.title) ?? parseTitleValue(event.customTitle);
  if (directTitle) {
    return directTitle;
  }

  if (
    event.kind === 1 &&
    Array.isArray(event.k) &&
    event.k.some((item) => item === 'customTitle')
  ) {
    const titleFromCustomEntry = parseTitleValue(event.v);
    if (titleFromCustomEntry) {
      return titleFromCustomEntry;
    }
  }

  if (isJsonObject(event.v)) {
    const nestedTitle = parseTitleValue(event.v.title) ?? parseTitleValue(event.v.customTitle);
    if (nestedTitle) {
      return nestedTitle;
    }
  }

  return null;
}

export function mergeSessionTitle(
  currentTitle: string | null | undefined,
  events: JsonObject[],
): string | null {
  let nextTitle = currentTitle ?? null;

  for (const event of events) {
    const title = getSessionTitle(event);
    if (title) {
      nextTitle = title;
    }
  }

  return nextTitle;
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

  const directTimestamp = parseTimestampFromRecord(event);
  if (directTimestamp !== null) {
    return directTimestamp;
  }

  const nestedDataTimestamp = parseTimestampFromUnknown(event.data);
  if (nestedDataTimestamp !== null) {
    return nestedDataTimestamp;
  }

  return parseTimestampFromUnknown(event.v);
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