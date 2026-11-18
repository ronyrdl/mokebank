import { EntitySchema, type EntitySchemaProperty } from '@mikro-orm/core';

type Field = Extract<EntitySchemaProperty<NonNullable<unknown>, Record<string, unknown>>, { type: unknown }>;

const id = { type: 'uuid', primary: true } as const;
const uuid = { type: 'uuid' } as const;
const text = { type: 'string' } as const;
const flag = { type: 'boolean' } as const;
const timestamp = { type: 'Date', columnType: 'timestamptz' } as const;
const integer = { type: 'number', columnType: 'integer' } as const;
const money = { type: 'decimal', precision: 20, scale: 2 } as const;
const rate = { type: 'decimal', precision: 24, scale: 10 } as const;
const json = { type: 'json', columnType: 'jsonb' } as const;

function nullable(field: Field): Field {
  return { ...field, nullable: true };
}

function entity(name: string, tableName: string, properties: Record<string, Field>) {
  return new EntitySchema<Record<string, unknown>>({ name, tableName, properties });
}

// The versioned SQL owns constraints, indexes, RLS and triggers.
export const entities = [
  entity('Tenant', 'tenants', { id, slug: text, name: text, active: flag, created_at: timestamp }),
  entity('TenantConfig', 'tenant_config', {
    tenant_id: id, currency: text, transaction_limit: money, fee_fixed: money,
    fee_percent: { type: 'decimal', precision: 7, scale: 4 },
  }),
  entity('User', 'users', {
    tenant_id: id, id, first_name: text, last_name: text, email: text, password_hash: text,
    role: text, active: flag, created_at: timestamp,
  }),
  entity('Account', 'accounts', {
    tenant_id: id, id, number: text, owner_id: uuid, currency: text, balance: money,
    status: text, created_at: timestamp,
  }),
  entity('Transaction', 'transactions', {
    tenant_id: id, id, user_id: uuid, type: text, source_account_id: nullable(uuid),
    destination_account_id: nullable(uuid), original_amount: money, converted_amount: nullable(money),
    source_currency: nullable(text), destination_currency: nullable(text), exchange_rate: nullable(rate),
    fee: money, status: text, description: nullable(text), failure_code: nullable(text),
    idempotency_key: uuid, correlation_id: text, created_at: timestamp,
  }),
  entity('ExchangeRate', 'exchange_rates', {
    tenant_id: id, source_currency: { ...text, primary: true }, destination_currency: { ...text, primary: true },
    rate, updated_at: timestamp,
  }),
  entity('IdempotencyRecord', 'idempotency_records', {
    tenant_id: id, user_id: id, key: id, fingerprint: text, status: text,
    http_status: nullable(integer), response_body: nullable(text), expires_at: timestamp,
  }),
  entity('AuditLog', 'audit_logs', {
    tenant_id: id, id, user_id: uuid, action: text, resource: text, previous_state: nullable(json),
    new_state: nullable(json), ip: text, correlation_id: text, created_at: timestamp,
  }),
  entity('WebhookConfig', 'webhook_config', { tenant_id: id, url: text, secret: text, active: flag, timeout_ms: integer }),
  entity('WebhookDelivery', 'webhook_deliveries', {
    tenant_id: id, id, event_id: uuid, attempt: integer, http_status: nullable(integer),
    error: nullable(text), created_at: timestamp,
  }),
  entity('OutboxEvent', 'outbox_events', {
    tenant_id: id, id, type: text, payload: json, correlation_id: text, webhook_url: nullable(text),
    webhook_secret: nullable(text), timeout_ms: nullable(integer), state: text, attempts: integer,
    next_attempt_at: timestamp, lease_token: nullable(uuid), created_at: timestamp,
  }),
  entity('RefreshToken', 'refresh_tokens', {
    tenant_id: id, id, user_id: uuid, token_hash: text, expires_at: timestamp, revoked_at: nullable(timestamp),
  }),
];
