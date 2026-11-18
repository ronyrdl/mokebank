import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import type { webhookInput, webhookPatch } from '../common/schemas.js';
import type { Identity, Trace } from '../common/types.js';
import { BankError, notFound } from '../common/errors.js';
import { audit } from '../audit/audit.service.js';
import { resolveEndpoint } from './endpoint.js';

type Webhook = { url: string; active: boolean; timeout_ms: number; secret: string };
const safe = (row: Webhook | undefined) => row
  ? { url: row.url, active: row.active, timeout_ms: row.timeout_ms, secret_configured: true }
  : null;

export function readWebhook(tx: DbSession, tenant: string) {
  return tx.one<Webhook>('SELECT url,active,timeout_ms,secret FROM webhook_config WHERE tenant_id=$1', tenant);
}

export async function writeWebhook(tx: DbSession, tenant: string, input: z.infer<typeof webhookInput>) {
  const row = await tx.one<Webhook>(`INSERT INTO webhook_config (tenant_id,url,active,timeout_ms,secret)
    VALUES ($1,$2,$3,$4,$5)
    ON CONFLICT (tenant_id) DO UPDATE SET url=excluded.url,active=excluded.active,
      timeout_ms=excluded.timeout_ms,secret=excluded.secret RETURNING url,active,timeout_ms,secret`,
    tenant, input.url, input.active ?? true, input.timeout_ms ?? 5000, input.secret);
  return safe(row);
}

export class WebhooksService {
  constructor(private readonly db: Database) {}

  get(actor: Identity) {
    return this.db.tenant(actor.tenant_id, async tx => safe(await readWebhook(tx, actor.tenant_id)));
  }

  async change(actor: Identity, trace: Trace, input: z.infer<typeof webhookPatch>, create: boolean) {
    if (input.url) await resolveEndpoint(input.url);
    return this.db.tenant(actor.tenant_id, async tx => {
      await tx.run('SELECT tenant_id FROM tenant_config WHERE tenant_id=$1 FOR UPDATE', actor.tenant_id);
      const previous = await readWebhook(tx, actor.tenant_id);
      if (!create && !previous) notFound('Webhook no configurado');
      if (create && previous) throw new BankError(409, 'WEBHOOK_EXISTS', 'El webhook ya existe');
      const next = await writeWebhook(tx, actor.tenant_id, {
        url: input.url ?? previous!.url,
        secret: input.secret ?? previous!.secret,
        active: input.active ?? previous?.active,
        timeout_ms: input.timeout_ms ?? previous?.timeout_ms,
      });
      await audit(tx, actor, trace, 'WEBHOOK_CONFIG_CHANGED', 'webhook', safe(previous), next);
      return next;
    });
  }
}

export { safe as publicWebhook };
