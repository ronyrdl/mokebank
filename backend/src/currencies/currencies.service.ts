import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import { currency, type rateInput } from '../common/schemas.js';
import type { Identity, Trace } from '../common/types.js';
import { BankError } from '../common/errors.js';
import { audit } from '../audit/audit.service.js';

export function readRates(tx: DbSession, tenant: string) {
  return tx.rows('SELECT * FROM exchange_rates WHERE tenant_id=$1 ORDER BY source_currency,destination_currency', tenant);
}

export async function writeRates(tx: DbSession, tenant: string, rates: z.infer<typeof rateInput>[]) {
  const pairs = new Set<string>();
  for (const rate of rates) {
    const pair = `${rate.source_currency}/${rate.destination_currency}`;
    if (pairs.has(pair)) throw new BankError(400, 'DUPLICATE_RATE', 'El par de monedas está duplicado');
    pairs.add(pair);
    await tx.run(`INSERT INTO exchange_rates (tenant_id,source_currency,destination_currency,rate)
      VALUES ($1,$2,$3,$4) ON CONFLICT (tenant_id,source_currency,destination_currency)
      DO UPDATE SET rate=excluded.rate,updated_at=now()`, tenant, rate.source_currency, rate.destination_currency, rate.rate);
  }
  return readRates(tx, tenant);
}

export class CurrenciesService {
  constructor(private readonly db: Database) {}

  list() {
    return currency.options;
  }

  rates(actor: Identity) {
    return this.db.tenant(actor.tenant_id, tx => readRates(tx, actor.tenant_id));
  }

  update(actor: Identity, trace: Trace, rates: z.infer<typeof rateInput>[]) {
    return this.db.tenant(actor.tenant_id, async tx => {
      await tx.run('SELECT tenant_id FROM tenant_config WHERE tenant_id=$1 FOR UPDATE', actor.tenant_id);
      const previous = await readRates(tx, actor.tenant_id);
      const next = await writeRates(tx, actor.tenant_id, rates);
      await audit(tx, actor, trace, 'EXCHANGE_RATES_CHANGED', 'exchange_rates', previous, next);
      return next;
    });
  }
}
