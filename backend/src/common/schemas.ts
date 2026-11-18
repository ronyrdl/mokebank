import { z } from 'zod';

export const uuid = z.uuid();
export const currency = z.enum(['COP', 'USD', 'EUR']);
export const accountNumber = z.string().trim().regex(/^\d{6,32}$/);
export const slug = z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9-]{1,62}$/);
export const email = z.email().max(254).toLowerCase();
export const password = z.string().min(12).max(72).refine(value => Buffer.byteLength(value) <= 72, 'Máximo 72 bytes');
export const money = z.string().regex(/^(0|[1-9]\d{0,17})(\.\d{1,2})?$/);
export const amount = money.refine(value => /[1-9]/.test(value), 'El monto debe ser positivo');
export const rate = z.string().regex(/^(0|[1-9]\d{0,13})(\.\d{1,10})?$/)
  .refine(value => /[1-9]/.test(value), 'La tasa debe ser positiva');
export const percent = z.string().regex(/^(\d{1,2}(\.\d{1,4})?|100(\.0{1,4})?)$/);
export const pageSchema = z.strictObject({
  page: z.string().regex(/^\d{1,5}$/).optional(),
  limit: z.string().regex(/^(?:[1-9]\d?|100)$/).optional(),
});

export function pagination(input: z.infer<typeof pageSchema>) {
  const page = Math.max(Number(input.page ?? '1'), 1);
  const limit = Number(input.limit ?? '20');
  return { page, limit, offset: (page - 1) * limit };
}

export const userInput = z.strictObject({
  first_name: z.string().trim().min(1).max(80),
  last_name: z.string().trim().min(1).max(80),
  email,
  password,
});

export const updateUser = userInput.omit({ password: true }).partial()
  .refine(value => Object.keys(value).length > 0, 'Envía al menos un campo');
export const userStatus = z.strictObject({ active: z.boolean() });
export const loginInput = z.strictObject({
  tenant_slug: slug,
  email,
  password: z.string().min(1).max(128),
});
export const accountInput = z.strictObject({ owner_id: uuid, currency, number: accountNumber.optional() });
export const updateAccount = z.strictObject({ number: accountNumber });
export const accountStatus = z.strictObject({ status: z.enum(['ACTIVE', 'INACTIVE', 'BLOCKED']) });
export const depositInput = z.strictObject({
  account_id: uuid, amount, description: z.string().trim().max(255).optional(),
});
export const transferQuoteInput = z.strictObject({
  source_account_id: uuid, destination_account_number: accountNumber,
  amount,
});
export const transferQuote = z.strictObject({
  original_amount: amount,
  source_currency: currency,
  destination_currency: currency,
  fee: money,
  exchange_rate: rate,
  total_debit: amount,
  converted_amount: amount,
  transaction_limit: amount,
});
export const transferInput = transferQuoteInput.extend({
  description: depositInput.shape.description,
  expected_quote: transferQuote.optional(),
});
export const transactionType = z.enum(['DEPOSIT', 'WITHDRAW', 'TRANSFER']);
export const historySchema = pageSchema.extend({
  type: transactionType.optional(),
  status: z.enum(['PENDING', 'COMPLETED', 'FAILED']).optional(),
  from: z.iso.datetime({ offset: true }).optional(),
  to: z.iso.datetime({ offset: true }).optional(),
  account_id: uuid.optional(),
  sort: z.enum(['asc', 'desc']).optional(),
}).refine(value => !value.from || !value.to || Date.parse(value.from) <= Date.parse(value.to), 'Rango de fechas inválido');
export const rateInput = z.strictObject({ source_currency: currency, destination_currency: currency, rate })
  .refine(value => value.source_currency !== value.destination_currency, 'Las monedas deben ser distintas');
export const ratesInput = z.strictObject({ rates: z.array(rateInput).max(6) });
export const webhookInput = z.strictObject({
  url: z.url().max(2048),
  secret: z.string().min(32).max(256),
  timeout_ms: z.number().int().min(500).max(15000).optional(),
  active: z.boolean().optional(),
});
export const webhookPatch = webhookInput.partial().refine(value => Object.keys(value).length > 0, 'Envía al menos un campo');
export const settingsFields = z.strictObject({
  currency, transaction_limit: amount, fee_fixed: money, fee_percent: percent,
  active: z.boolean(),
});
export const settingsPatch = settingsFields.partial().extend({
  rates: ratesInput.shape.rates.optional(), webhook: webhookInput.optional(),
}).refine(value => Object.keys(value).length > 0, 'Envía al menos un campo');
export const tenantInput = settingsFields.omit({ active: true }).extend({
  name: z.string().trim().min(1).max(120),
  slug,
  admin: userInput,
  rates: ratesInput.shape.rates.optional(),
  webhook: webhookInput.optional(),
});
