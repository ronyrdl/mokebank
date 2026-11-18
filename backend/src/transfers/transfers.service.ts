import type { DbSession } from '../database/database.js';
import type { Account, Identity } from '../common/types.js';
import { BankError, notFound } from '../common/errors.js';
import { asMoney, convertedAmount, scaled, transferFee } from '../fees/money.js';
import type { TenantConfig } from '../tenants/tenants.service.js';

export function assertActive(account: Account) {
  if (account.status !== 'ACTIVE') throw new BankError(409, 'ACCOUNT_NOT_ACTIVE', 'La cuenta no está activa');
}

export async function transfer(tx: DbSession, actor: Identity, input: {
  source_account_id: string; destination_account_number: string;
}, amount: bigint, config: TenantConfig, lockAccounts: boolean) {
  const rows = await tx.rows<Account>(`SELECT * FROM accounts
    WHERE tenant_id=$1 AND (id=$2 OR number=$3) ORDER BY id ${lockAccounts ? 'FOR UPDATE' : ''}`,
    actor.tenant_id, input.source_account_id, input.destination_account_number);
  const source = rows.find(row => row.id === input.source_account_id
    && row.owner_id === actor.user_id);
  if (!source) notFound('Cuenta de origen no encontrada');
  const destination = rows.find(row => row.number === input.destination_account_number);
  if (!destination) notFound('Cuenta de destino no encontrada');
  if (source.id === destination.id) throw new BankError(400, 'SAME_ACCOUNT', 'Las cuentas deben ser distintas');
  assertActive(source);
  assertActive(destination);

  let rate = '1';
  if (source.currency !== destination.currency) {
    const exchange = await tx.one<{ rate: string }>(`SELECT rate FROM exchange_rates
      WHERE tenant_id=$1 AND source_currency=$2 AND destination_currency=$3`,
      actor.tenant_id, source.currency, destination.currency);
    if (!exchange) throw new BankError(422, 'EXCHANGE_RATE_MISSING', 'Tasa de cambio no configurada');
    rate = exchange.rate;
  }

  const fee = transferFee(amount, config.fee_fixed, config.fee_percent);
  const sourceBalance = scaled(source.balance, 2) - amount - fee;
  if (sourceBalance < 0n) throw new BankError(422, 'INSUFFICIENT_FUNDS', 'Saldo insuficiente');
  const converted = convertedAmount(amount, rate);
  if (converted === 0n) throw new BankError(422, 'AMOUNT_TOO_SMALL', 'El importe convertido redondea a cero');
  const destinationBalance = scaled(destination.balance, 2) + converted;
  const pricing = {
    original_amount: asMoney(amount),
    source_currency: source.currency,
    destination_currency: destination.currency,
    fee: asMoney(fee),
    exchange_rate: rate,
    total_debit: asMoney(amount + fee),
    converted_amount: asMoney(converted),
  };
  return { source, destination, sourceBalance: asMoney(sourceBalance),
    destinationBalance: asMoney(destinationBalance), pricing };
}
