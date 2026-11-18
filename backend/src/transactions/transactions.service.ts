import { randomUUID } from 'node:crypto';
import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import type { Identity, Trace } from '../common/types.js';
import { BankError, forbidden, notFound, unauthorized } from '../common/errors.js';
import { pagination, type depositInput, type historySchema, type transferInput, type transferQuoteInput, type transactionType } from '../common/schemas.js';
import { failure, success } from '../common/response.js';
import { findAccount } from '../accounts/accounts.service.js';
import { asMoney, scaled } from '../fees/money.js';
import { assertActive, transfer } from '../transfers/transfers.service.js';
import { enqueue } from '../webhooks/outbox.js';
import type { TenantConfig } from '../tenants/tenants.service.js';
import type { IdempotencyService } from '../idempotency/idempotency.service.js';

type Input = z.infer<typeof depositInput> | z.infer<typeof transferInput>;
type QuoteInput = z.infer<typeof transferQuoteInput>;
type Operation = z.infer<typeof transactionType>;
type History = z.infer<typeof historySchema>;
type Entry = { id: string; tenant_id: string; status: string };

function amountOutOfRange() {
  return new BankError(422, 'AMOUNT_OUT_OF_RANGE', 'Importe fuera del rango permitido');
}

export class TransactionsService {
  constructor(private readonly db: Database, private readonly idempotency: IdempotencyService) {}

  async quote(actor: Identity, input: QuoteInput) {
    if (actor.role !== 'CLIENT') forbidden();
    try {
      return await this.db.tenant(actor.tenant_id, async tx => {
        const { amount, config } = await this.prepare(tx, actor, input.amount);
        const { pricing } = await transfer(tx, actor, input, amount, config, false);
        return { ...pricing, transaction_limit: config.transaction_limit };
      });
    } catch (cause) {
      if (cause instanceof RangeError) throw amountOutOfRange();
      throw cause;
    }
  }

  execute(actor: Identity, trace: Trace, key: string, type: Operation, input: Input) {
    if (actor.role !== 'CLIENT') forbidden();
    return this.idempotency.execute(actor, key, type, input, async tx => {
      try {
        const row = await tx.atomic(nested => this.post(nested, actor, trace, key, type, input));
        return { status: 201, body: JSON.stringify(success(row, trace, 'OPERATION_COMPLETED')) };
      } catch (cause) {
        const error = cause instanceof RangeError ? amountOutOfRange() : cause;
        if (!(error instanceof BankError) || error.status === 401) throw error;
        await tx.run(`INSERT INTO transactions
          (tenant_id,id,user_id,type,original_amount,fee,status,description,failure_code,idempotency_key,correlation_id)
          VALUES ($1,$2,$3,$4,$5,0,'FAILED',$6,$7,$8,$9)`,
          actor.tenant_id, randomUUID(), actor.user_id, type, input.amount, input.description ?? null, error.code, key, trace.correlationId);
        return { status: error.status, body: JSON.stringify(failure(error, trace)) };
      }
    });
  }

  private async prepare(tx: DbSession, actor: Identity, inputAmount: string) {
    const tenant = actor.tenant_id;
    if (!await tx.one('SELECT id FROM tenants WHERE id=$1 AND active FOR SHARE', tenant)) unauthorized();
    if (!await tx.one('SELECT id FROM users WHERE tenant_id=$1 AND id=$2 AND active FOR SHARE', tenant, actor.user_id)) unauthorized();
    const config = await tx.one<TenantConfig>('SELECT * FROM tenant_config WHERE tenant_id=$1 FOR SHARE', tenant);
    if (!config) throw new Error('Missing tenant configuration');
    const amount = scaled(inputAmount, 2);
    if (amount > scaled(config.transaction_limit, 2)) {
      throw new BankError(422, 'TRANSACTION_LIMIT_EXCEEDED', 'El monto excede el límite por transacción');
    }

    return { amount, config };
  }

  private async post(tx: DbSession, actor: Identity, trace: Trace, key: string, type: Operation, input: Input) {
    const tenant = actor.tenant_id;
    const { amount, config } = await this.prepare(tx, actor, input.amount);
    let sourceId: string | null = null;
    let destinationId: string | null = null;
    let originalCurrency: string;
    let convertedCurrency: string;
    let converted = asMoney(amount);
    let fee = '0.00';
    let rate = '1';

    if ('source_account_id' in input) {
      const result = await transfer(tx, actor, input, amount, config, true);
      const { pricing } = result;
      if (input.expected_quote) {
        const { expected_quote: expected } = input;
        const changed = expected.source_currency !== pricing.source_currency
          || expected.destination_currency !== pricing.destination_currency
          || scaled(expected.exchange_rate, 10) !== scaled(pricing.exchange_rate, 10)
          || scaled(expected.transaction_limit, 2) !== scaled(config.transaction_limit, 2)
          || (['original_amount', 'fee', 'total_debit', 'converted_amount'] as const)
            .some(field => scaled(expected[field], 2) !== scaled(pricing[field], 2));
        if (changed) throw new BankError(409, 'QUOTE_CHANGED', 'La cotización cambió. Solicita una nueva cotización');
      }
      sourceId = result.source.id;
      destinationId = result.destination.id;
      originalCurrency = result.source.currency;
      convertedCurrency = result.destination.currency;
      ({ converted_amount: converted, fee, exchange_rate: rate } = pricing);
      await this.setBalance(tx, tenant, sourceId, result.sourceBalance);
      await this.setBalance(tx, tenant, destinationId, result.destinationBalance);
    } else {
      const account = await findAccount(tx, actor, input.account_id, true);
      assertActive(account);
      const balance = scaled(account.balance, 2);
      originalCurrency = convertedCurrency = account.currency;
      if (type === 'DEPOSIT') {
        destinationId = account.id;
        await this.setBalance(tx, tenant, account.id, asMoney(balance + amount));
      } else {
        sourceId = account.id;
        if (balance < amount) throw new BankError(422, 'INSUFFICIENT_FUNDS', 'Saldo insuficiente');
        await this.setBalance(tx, tenant, account.id, asMoney(balance - amount));
      }
    }

    const row = await tx.one<Entry>(`INSERT INTO transactions
      (tenant_id,id,user_id,type,source_account_id,destination_account_id,original_amount,
       converted_amount,source_currency,destination_currency,exchange_rate,fee,status,description,idempotency_key,correlation_id)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'COMPLETED',$13,$14,$15) RETURNING *`,
      tenant, randomUUID(), actor.user_id, type, sourceId, destinationId, asMoney(amount), converted,
      originalCurrency, convertedCurrency, rate, fee, input.description ?? null, key, trace.correlationId);
    await enqueue(tx, tenant, type, trace, row);
    return row;
  }

  private setBalance(tx: DbSession, tenant: string, account: string, balance: string) {
    return tx.run('UPDATE accounts SET balance=$3 WHERE tenant_id=$1 AND id=$2', tenant, account, balance);
  }

  async history(actor: Identity, input: History, id?: string, accountId?: string) {
    const { page, limit, offset } = pagination(input);
    return this.db.tenant(actor.tenant_id, async tx => {
      const account = accountId ?? input.account_id;
      if (account) await findAccount(tx, actor, account);
      const rows = await tx.rows<Entry>(`SELECT t.* FROM transactions t WHERE t.tenant_id=$1
        AND ($2::boolean OR t.user_id=$3 OR EXISTS (
          SELECT 1 FROM accounts a WHERE a.tenant_id=t.tenant_id AND a.owner_id=$3
          AND a.id IN (t.source_account_id,t.destination_account_id)))
        AND ($4::uuid IS NULL OR t.id=$4)
        AND ($5::uuid IS NULL OR $5 IN (t.source_account_id,t.destination_account_id))
        AND ($6::text IS NULL OR t.type=$6)
        AND ($7::text IS NULL OR t.status=$7)
        AND ($8::timestamptz IS NULL OR t.created_at >= $8)
        AND ($9::timestamptz IS NULL OR t.created_at <= $9)
        ORDER BY t.created_at ${input.sort === 'asc' ? 'ASC' : 'DESC'},t.id DESC LIMIT $10 OFFSET $11`,
        actor.tenant_id, actor.role === 'ADMIN', actor.user_id, id ?? null, account ?? null,
        input.type ?? null, input.status ?? null, input.from ?? null, input.to ?? null, limit + 1, offset);
      if (id) return rows[0] ?? notFound('Transacción no encontrada');
      return { items: rows.slice(0, limit), page, limit, has_more: rows.length > limit };
    });
  }

  stats(actor: Identity) {
    return this.db.tenant(actor.tenant_id, tx => tx.rows(`SELECT type,status,count(*)::text AS count
      FROM transactions WHERE tenant_id=$1 GROUP BY type,status ORDER BY type,status`, actor.tenant_id));
  }
}
