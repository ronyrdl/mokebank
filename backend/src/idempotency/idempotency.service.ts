import { createHash, randomUUID } from 'node:crypto';
import type { Redis } from 'ioredis';
import type { Database, DbSession } from '../database/database.js';
import type { Identity } from '../common/types.js';
import { BankError } from '../common/errors.js';

type Outcome = { status: number; body: string };
type RecordRow = {
  fingerprint: string; http_status: number; response_body: string;
  expired: boolean; status: 'PROCESSING' | 'COMPLETED';
};

export class IdempotencyService {
  constructor(private readonly db: Database, private readonly redis: Redis) {}

  async execute(actor: Identity, key: string, type: string, input: object,
    operation: (tx: DbSession) => Promise<Outcome>): Promise<Outcome> {
    const scope = `bankos:idem:${actor.tenant_id}:${actor.user_id}:${key}`;
    const token = randomUUID();
    const canonical = Object.entries(input).sort(([left], [right]) => left.localeCompare(right));
    const fingerprint = createHash('sha256').update(JSON.stringify([type, canonical])).digest('hex');
    const busy = () => new BankError(409, 'OPERATION_PROCESSING', 'La operación está en proceso');
    let acquired;
    try {
      acquired = await this.redis.set(scope, token, 'PX', 30_000, 'NX');
    } catch {
      throw new BankError(503, 'COORDINATION_UNAVAILABLE', 'Coordinación temporalmente no disponible');
    }
    if (acquired !== 'OK') throw busy();

    try {
      return await this.db.tenant(actor.tenant_id, async tx => {
        const lock = await tx.one<{ acquired: boolean }>('SELECT pg_try_advisory_xact_lock(hashtextextended($1,0)) AS acquired', scope);
        if (!lock?.acquired) throw busy();
        const current = await tx.one<RecordRow>(`SELECT fingerprint,http_status,response_body,status,expires_at <= now() AS expired
          FROM idempotency_records WHERE tenant_id=$1 AND user_id=$2 AND key=$3`, actor.tenant_id, actor.user_id, key);
        if (current) {
          if (current.expired) throw new BankError(409, 'IDEMPOTENCY_EXPIRED', 'La clave venció y ya fue utilizada');
          if (current.fingerprint !== fingerprint) throw new BankError(409, 'IDEMPOTENCY_MISMATCH', 'La clave ya se usó con otra solicitud');
          if (current.status === 'PROCESSING') throw busy();
          return { status: current.http_status, body: current.response_body };
        }
        await tx.run(`INSERT INTO idempotency_records (tenant_id,user_id,key,fingerprint,status,expires_at)
          VALUES ($1,$2,$3,$4,'PROCESSING',now()+interval '24 hours')`, actor.tenant_id, actor.user_id, key, fingerprint);
        const result = await operation(tx);
        await tx.run(`UPDATE idempotency_records SET status='COMPLETED',http_status=$4,response_body=$5,
          expires_at=clock_timestamp()+interval '24 hours' WHERE tenant_id=$1 AND user_id=$2 AND key=$3`,
          actor.tenant_id, actor.user_id, key, result.status, result.body);
        return result;
      });
    } finally {
      try {
        await this.redis.eval("if redis.call('GET',KEYS[1])==ARGV[1] then return redis.call('DEL',KEYS[1]) end return 0",
          1, scope, token);
      } catch {
        // The lease expires even if Redis disconnects after the database commits.
      }
    }
  }
}
