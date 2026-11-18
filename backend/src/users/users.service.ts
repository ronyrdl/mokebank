import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import { pagination, type userInput, type updateUser, type pageSchema } from '../common/schemas.js';
import { BankError, notFound } from '../common/errors.js';
import { userFields, type Identity, type Role, type Trace, type User } from '../common/types.js';
import { audit } from '../audit/audit.service.js';

export async function insertUser(tx: DbSession, tenant: string, input: z.infer<typeof userInput>, role: Role) {
  const hash = await bcrypt.hash(input.password, 12);
  const user = await tx.one<User>(`INSERT INTO users (tenant_id,id,first_name,last_name,email,password_hash,role)
    VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING ${userFields}`,
    tenant, randomUUID(), input.first_name, input.last_name, input.email, hash, role);
  return user!;
}

export class UsersService {
  constructor(private readonly db: Database) {}

  create(actor: Identity, trace: Trace, input: z.infer<typeof userInput>) {
    return this.db.tenant(actor.tenant_id, async tx => {
      const user = await insertUser(tx, actor.tenant_id, input, 'CLIENT');
      await audit(tx, actor, trace, 'USER_CREATED', user.id, null, user);
      return user;
    });
  }

  list(actor: Identity, input: z.infer<typeof pageSchema>) {
    const { page, limit, offset } = pagination(input);
    return this.db.tenant(actor.tenant_id, async tx => {
      const rows = await tx.rows<User>(`SELECT ${userFields} FROM users WHERE tenant_id=$1
        ORDER BY created_at DESC,id DESC LIMIT $2 OFFSET $3`, actor.tenant_id, limit + 1, offset);
      return { items: rows.slice(0, limit), page, limit, has_more: rows.length > limit };
    });
  }

  get(actor: Identity, id: string) {
    return this.db.tenant(actor.tenant_id, tx => this.find(tx, actor, id));
  }

  update(actor: Identity, trace: Trace, id: string, input: z.infer<typeof updateUser>) {
    return this.db.tenant(actor.tenant_id, async tx => {
      const previous = await this.find(tx, actor, id, true);
      const next = await tx.one<User>(`UPDATE users SET first_name=$3,last_name=$4,email=$5
        WHERE tenant_id=$1 AND id=$2 RETURNING ${userFields}`,
        actor.tenant_id, id, input.first_name ?? previous.first_name,
        input.last_name ?? previous.last_name, input.email ?? previous.email);
      await audit(tx, actor, trace, 'USER_UPDATED', id, previous, next);
      return next;
    });
  }

  status(actor: Identity, trace: Trace, id: string, active: boolean) {
    return this.db.tenant(actor.tenant_id, async tx => {
      const previous = await this.find(tx, actor, id, true);
      if (previous.role === 'ADMIN' && !active) throw new BankError(409, 'ADMIN_REQUIRED', 'El administrador debe permanecer activo');
      const next = await tx.one<User>(`UPDATE users SET active=$3
        WHERE tenant_id=$1 AND id=$2 RETURNING ${userFields}`, actor.tenant_id, id, active);
      if (!active) await tx.run(`UPDATE refresh_tokens SET revoked_at=now()
        WHERE tenant_id=$1 AND user_id=$2 AND revoked_at IS NULL`, actor.tenant_id, id);
      await audit(tx, actor, trace, 'USER_STATUS_CHANGED', id, previous, next);
      return next;
    });
  }

  private async find(tx: DbSession, actor: Identity, id: string, lock = false) {
    const user = await tx.one<User>(`SELECT ${userFields} FROM users
      WHERE tenant_id=$1 AND id=$2 ${lock ? 'FOR UPDATE' : ''}`, actor.tenant_id, id);
    return user ?? notFound('Usuario no encontrado');
  }
}
