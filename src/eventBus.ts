import { EventEmitter } from 'node:events';
import type { NewEventsPayload } from './types';

class ObserverEventBus extends EventEmitter {
  constructor() {
    super();
    this.setMaxListeners(0);
  }

  emitNewEvents(payload: NewEventsPayload): void {
    this.emit('new-events', payload);
  }

  subscribe(listener: (payload: NewEventsPayload) => void): () => void {
    this.on('new-events', listener);
    return () => this.off('new-events', listener);
  }
}

export const eventBus = new ObserverEventBus();