import { setTimeout as sleep } from 'node:timers/promises';
import { Database } from './database/database.js';
import { integerSetting } from './common/config.js';
import { OutboxWorker } from './webhooks/outbox.js';

const stop = new AbortController();
for (const signal of ['SIGTERM', 'SIGINT'] as const) process.once(signal, () => stop.abort());

const db = await Database.open();
const worker = new OutboxWorker(db);
const interval = integerSetting('WEBHOOK_POLL_MS', 1000);
try {
  while (!stop.signal.aborted) {
    try {
      await worker.tick();
    } catch {
      console.error(JSON.stringify({ message: 'webhook.worker_error' }));
    }
    if (!stop.signal.aborted) await sleep(interval, undefined, { signal: stop.signal }).catch(() => {});
  }
} finally {
  await db.close();
}
