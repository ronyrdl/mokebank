import { createHmac, randomUUID } from 'node:crypto';
import type { Database, DbSession } from '../database/database.js';
import { integerSetting } from '../common/config.js';
import type { Trace } from '../common/types.js';
import { readWebhook } from './webhooks.service.js';
import { sendWebhook } from './endpoint.js';

export async function enqueue(tx: DbSession, tenant: string, type: string, trace: Trace, transaction: unknown) {
  const webhook = await readWebhook(tx, tenant);
  const eventId = randomUUID();
  const event = `transaction.${type.toLowerCase()}.completed`;
  const payload = { id: eventId, type: event, tenant_id: tenant, occurred_at: new Date().toISOString(),
    correlation_id: trace.correlationId, data: transaction };
  await tx.run(`INSERT INTO outbox_events (tenant_id,id,type,payload,correlation_id,
    webhook_url,webhook_secret,timeout_ms,state)
    VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7,$8,$9)`,
    tenant, eventId, event, JSON.stringify(payload), trace.correlationId,
    webhook?.active ? webhook.url : null, webhook?.active ? webhook.secret : null,
    webhook?.active ? webhook.timeout_ms : null, webhook?.active ? 'PENDING' : 'SKIPPED');
}

type OutboxEvent = {
  id: string; tenant_id: string; payload: unknown; correlation_id: string; webhook_url: string;
  webhook_secret: string; timeout_ms: number; attempts: number; lease_token: string;
};

export class OutboxWorker {
  private readonly maxAttempts = integerSetting('WEBHOOK_MAX_ATTEMPTS', 6);

  constructor(private readonly db: Database, private readonly send = sendWebhook) {}

  async tick() {
    const tenants = await this.db.connection().rows<{ tenant_id: string }>('SELECT outbox_tenants() AS tenant_id');
    for (const { tenant_id: tenant } of tenants) {
      const event = await this.claim(tenant);
      if (event) await this.deliver(event);
    }
  }

  private claim(tenant: string) {
    return this.db.tenant(tenant, tx => tx.one<OutboxEvent>(`WITH next AS (
      SELECT id FROM outbox_events WHERE tenant_id=$1 AND state='PENDING' AND next_attempt_at <= now()
      ORDER BY next_attempt_at,id LIMIT 1 FOR UPDATE SKIP LOCKED
    ) UPDATE outbox_events e SET lease_token=$2,next_attempt_at=now()+interval '60 seconds'
      FROM next WHERE e.tenant_id=$1 AND e.id=next.id RETURNING e.*`, tenant, randomUUID()));
  }

  private async deliver(event: OutboxEvent) {
    const attempt = event.attempts + 1;
    const body = JSON.stringify(event.payload);
    const timestamp = String(Math.floor(Date.now() / 1000));
    const signature = createHmac('sha256', event.webhook_secret).update(`${timestamp}.${body}`).digest('hex');
    let status: number | null = null;
    let error: string | null = null;
    try {
      status = await this.send(event.webhook_url, body, {
        'x-bankos-signature': `sha256=${signature}`, 'x-bankos-timestamp': timestamp,
        'x-bankos-event-id': event.id, 'x-correlation-id': event.correlation_id,
      }, event.timeout_ms);
      if (status < 200 || status >= 300) error = 'HTTP_ERROR';
    } catch {
      error = 'DELIVERY_ERROR';
    }

    await this.db.tenant(event.tenant_id, async tx => {
      const state = error === null ? 'DELIVERED' : attempt >= this.maxAttempts ? 'FAILED' : 'PENDING';
      const delay = Math.min(2 ** Math.min(attempt, 12) * 5, 3600);
      const updated = await tx.one(`UPDATE outbox_events SET attempts=$4,state=$5,lease_token=NULL,
        next_attempt_at=now()+$6*interval '1 second',
        webhook_secret=CASE WHEN $5='PENDING' THEN webhook_secret ELSE NULL END
        WHERE tenant_id=$1 AND id=$2 AND lease_token=$3 RETURNING id`,
        event.tenant_id, event.id, event.lease_token, attempt, state, delay);
      if (!updated) return;
      await tx.run(`INSERT INTO webhook_deliveries (tenant_id,event_id,attempt,http_status,error)
        VALUES ($1,$2,$3,$4,$5)`, event.tenant_id, event.id, attempt, status, error);
    });
    console.log(JSON.stringify({ message: 'webhook.delivery', correlationId: event.correlation_id,
      eventId: event.id, attempt, status, error }));
  }
}
