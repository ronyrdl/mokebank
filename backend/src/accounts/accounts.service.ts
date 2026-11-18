import { randomInt, randomUUID } from 'node:crypto';
import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import { pagination, type accountInput, type accountStatus, type pageSchema } from '../common/schemas.js';
import { notFound } from '../common/errors.js';
import type { Account, Identity, Trace } from '../common/types.js';
import { audit } from '../audit/audit.service.js';

export async function findAccount(tx: DbSession, actor: Identity, id: string, lock = false) {
  const row = await tx.one<Account>(`SELECT * FROM accounts WHERE tenant_id=$1 AND id=$2
    AND ($3::boolean OR owner_id=$4) ${lock ? 'FOR UPDATE' : ''}`,
    actor.tenant_id, id, actor.role === 'ADMIN', actor.user_id);
  return row ?? notFound('Cuenta no encontrada');
}

export class AccountsService {
  constructor(private readonly db: Database) {}

  create(actor: Identity, trace: Trace, input: z.infer<typeof accountInput>) {
    return this.db.tenant(actor.tenant_id, async tx => {
      if (!await tx.one(`SELECT id FROM users WHERE tenant_id=$1 AND id=$2 AND role='CLIENT' AND active FOR SHARE`,
        actor.tenant_id, input.owner_id)) notFound('Titular no encontrado');
      const number = input.number ?? randomInt(100_000_000_000, 1_000_000_000_000).toString();
      const row = await tx.one<Account>(`INSERT INTO accounts (tenant_id,id,number,owner_id,currency)
        VALUES ($1,$2,$3,$4,$5) RETURNING *`, actor.tenant_id, randomUUID(), number, input.owner_id, input.currency);
      await audit(tx, actor, trace, 'ACCOUNT_CREATED', row!.id, null, row);
      return row;
    });
  }

  list(actor: Identity, input: z.infer<typeof pageSchema>) {
    const { page, limit, offset } = pagination(input);
    return this.db.tenant(actor.tenant_id, async tx => {
      const rows = await tx.rows<Account>(`SELECT * FROM accounts WHERE tenant_id=$1
        AND ($2::boolean OR owner_id=$3) ORDER BY created_at DESC,id DESC LIMIT $4 OFFSET $5`,
        actor.tenant_id, actor.role === 'ADMIN', actor.user_id, limit + 1, offset);
      return { items: rows.slice(0, limit), page, limit, has_more: rows.length > limit };
    });
  }

  get(actor: Identity, id: string) {
    return this.db.tenant(actor.tenant_id, tx => findAccount(tx, actor, id));
  }

  update(actor: Identity, trace: Trace, id: string, number: string) {
    return this.db.tenant(actor.tenant_id, async tx => {
      const previous = await findAccount(tx, actor, id, true);
      const next = await tx.one<Account>('UPDATE accounts SET number=$3 WHERE tenant_id=$1 AND id=$2 RETURNING *',
        actor.tenant_id, id, number);
      await audit(tx, actor, trace, 'ACCOUNT_UPDATED', id, previous, next);
      return next;
    });
  }

  status(actor: Identity, trace: Trace, id: string, status: z.infer<typeof accountStatus>['status']) {
    return this.db.tenant(actor.tenant_id, async tx => {
      const previous = await findAccount(tx, actor, id, true);
      const next = await tx.one<Account>('UPDATE accounts SET status=$3 WHERE tenant_id=$1 AND id=$2 RETURNING *',
        actor.tenant_id, id, status);
      let action = 'ACCOUNT_STATUS_CHANGED';
      if (status === 'BLOCKED') action = 'ACCOUNT_BLOCKED';
      else if (previous.status === 'BLOCKED' && status === 'ACTIVE') action = 'ACCOUNT_UNBLOCKED';
      await audit(tx, actor, trace, action, id, previous, next);
      return next;
    });
  }
}
