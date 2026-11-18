import type { Database, DbSession } from '../database/database.js';
import type { Identity, Trace } from '../common/types.js';
import type { pageSchema } from '../common/schemas.js';
import { pagination } from '../common/schemas.js';
import type { z } from 'zod';

export async function audit(tx: DbSession, identity: Identity, trace: Trace, action: string,
  resource: string, previous: unknown, next: unknown) {
  await tx.run(`INSERT INTO audit_logs
    (tenant_id,user_id,action,resource,previous_state,new_state,ip,correlation_id)
    VALUES ($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7,$8)`,
    identity.tenant_id, identity.user_id, action, resource, JSON.stringify(previous), JSON.stringify(next),
    trace.ip, trace.correlationId);
}

export class AuditService {
  constructor(private readonly db: Database) {}

  async list(actor: Identity, input: z.infer<typeof pageSchema>) {
    const { page, limit, offset } = pagination(input);
    const rows = await this.db.tenant(actor.tenant_id, tx => tx.rows(
      'SELECT * FROM audit_logs WHERE tenant_id=$1 ORDER BY created_at DESC,id DESC LIMIT $2 OFFSET $3',
      actor.tenant_id, limit + 1, offset));
    return { items: rows.slice(0, limit), page, limit, has_more: rows.length > limit };
  }
}
