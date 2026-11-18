import { z } from 'zod';
import { accountStatus, currency, transactionType, uuid } from './schemas.js';

const dateTime = z.string().meta({ format: 'date-time' });
const decimal = z.string().meta({ description: 'Valor decimal como cadena' });
const status = z.enum(['PENDING', 'COMPLETED', 'FAILED']);

export const userResponse = z.object({
  id: uuid, tenant_id: uuid, first_name: z.string(), last_name: z.string(), email: z.email(),
  role: z.enum(['ADMIN', 'CLIENT']), active: z.boolean(), created_at: dateTime,
}).meta({ title: 'User' });

export const sessionResponse = z.object({
  user: userResponse, access_token: z.string(), token_type: z.literal('Bearer'), expires_in: z.number().int(),
}).meta({ title: 'Session' });

export const logoutResponse = z.object({ logged_out: z.boolean() });

export const accountResponse = z.object({
  id: uuid, tenant_id: uuid, owner_id: uuid, number: z.string(), currency, balance: decimal,
  status: accountStatus.shape.status, created_at: dateTime,
}).meta({ title: 'Account' });

export const selfRegistrationResponse = z.object({ user: userResponse, account: accountResponse });

export const transactionResponse = z.object({
  id: uuid, tenant_id: uuid, user_id: uuid, type: transactionType,
  source_account_id: uuid.nullable(), destination_account_id: uuid.nullable(),
  original_amount: decimal, converted_amount: decimal.nullable(),
  source_currency: currency.nullable(), destination_currency: currency.nullable(),
  exchange_rate: decimal.nullable(), fee: decimal, status,
  description: z.string().nullable(), failure_code: z.string().nullable(),
  idempotency_key: uuid, correlation_id: z.string(), created_at: dateTime,
}).meta({ title: 'Transaction' });

export const transactionStatsResponse = z.array(z.object({ type: transactionType, status, count: z.string() }));
export const currencyListResponse = z.array(currency);
export const ratesResponse = z.array(z.object({
  tenant_id: uuid, source_currency: currency, destination_currency: currency, rate: decimal, updated_at: dateTime,
}).meta({ title: 'ExchangeRate' }));

export const webhookResponse = z.object({
  url: z.url(), active: z.boolean(), timeout_ms: z.number().int(), secret_configured: z.boolean(),
}).meta({ title: 'WebhookConfig' });
export const nullableWebhookResponse = webhookResponse.nullable();

export const tenantStatusResponse = z.object({ id: uuid, active: z.boolean() });
export const tenantConfigResponse = tenantStatusResponse.extend({
  slug: z.string(), name: z.string(), currency, transaction_limit: decimal,
  fee_fixed: decimal, fee_percent: decimal, rates: ratesResponse, webhook: nullableWebhookResponse,
}).meta({ title: 'TenantConfig' });
export const tenantCreatedResponse = tenantConfigResponse.extend({ admin: userResponse });

export const healthResponse = z.object({
  status: z.literal('up'), postgres: z.literal('up'), redis: z.literal('up'),
});

export function paginatedResponse(item: z.ZodType) {
  return z.object({
    items: z.array(item), page: z.number().int(), limit: z.number().int(), has_more: z.boolean(),
  });
}

export const tenantDirectoryResponse = paginatedResponse(z.object({ slug: z.string(), name: z.string() }));
export const platformSessionResponse = z.object({
  access_token: z.string(), token_type: z.literal('Bearer'), expires_in: z.number().int(),
});

export const accountListResponse = paginatedResponse(accountResponse);
export const userListResponse = paginatedResponse(userResponse);
export const transactionListResponse = paginatedResponse(transactionResponse);
export const auditListResponse = paginatedResponse(z.object({
  id: uuid, tenant_id: uuid, user_id: uuid, action: z.string(), resource: z.string(),
  previous_state: z.unknown(), new_state: z.unknown(),
  ip: z.string(), correlation_id: z.string(), created_at: dateTime,
}).meta({ title: 'AuditEntry' }));
