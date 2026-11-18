import { createHash, randomUUID } from 'node:crypto';
import { afterAll, beforeAll, expect, jest, test } from '@jest/globals';
import { SignJWT } from 'jose';
import { createApp } from '../dist/app.js';
import { Database } from '../dist/database/database.js';
import { OutboxWorker } from '../dist/webhooks/outbox.js';
import { REDIS } from '../dist/common/redis.js';

jest.setTimeout(45_000);
const password = 'Test-demo-password!';
const marker = randomUUID().slice(0, 8);
const webhookSecret = 'test-webhook-secret-at-least-32-characters';
let app;
let db;
let base;
let a;
let b;
let client;
let usd;
let cop;
let foreign;
let other;

async function start() {
  app = await createApp();
  await app.listen(0, '127.0.0.1');
  base = `${await app.getUrl()}/api/v1`;
}

async function call(path, { token, body, method, headers = {} } = {}) {
  const res = await fetch(base + path, {
    method: method ?? (body === undefined ? 'GET' : 'POST'),
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, text, json: JSON.parse(text), headers: res.headers };
}

function data(result, status = 200) {
  if (result.status !== status) throw new Error(`Expected ${status}, received ${result.status} ${result.text}`);
  return result.json.data;
}

const login = (slug, email, secret = password) => call('/auth/login', {
  body: { tenant_slug: slug, email, password: secret },
});
const operation = (type, token, body, key = randomUUID()) => call(`/transactions/${type}`, {
  token, body, headers: { 'Idempotency-Key': key, 'X-Correlation-ID': 'bankos-integration' },
});
const balance = async (account, token) => data(await call(`/accounts/${account.id}`, { token })).balance;

async function provision(label) {
  const slug = `e2e-${marker}-${label}`;
  const email = 'admin@example.test';
  const tenant = data(await call('/tenants', {
    headers: { 'X-Platform-Key': process.env.PLATFORM_ADMIN_KEY },
    body: { name: slug, slug, currency: 'COP', transaction_limit: '1000000', fee_fixed: '1.00', fee_percent: '1.50',
      admin: { first_name: 'Admin', last_name: 'Test', email, password },
      rates: [{ source_currency: 'USD', destination_currency: 'COP', rate: '4000' }] },
  }), 201);
  return { id: tenant.id, slug, email, token: data(await login(slug, email)).access_token };
}

async function createClient(bank, label, currency, number) {
  const email = `${label}@example.test`;
  const user = data(await call('/users', {
    token: bank.token, body: { first_name: label, last_name: 'Test', email, password },
  }), 201);
  const account = data(await call('/accounts', {
    token: bank.token, body: { owner_id: user.id, currency, number },
  }), 201);
  return { user, account, token: data(await login(bank.slug, email)).access_token };
}

beforeAll(async () => {
  await start();
  db = app.get(Database);
  a = await provision('a');
  b = await provision('b');
  client = await createClient(a, 'alice', 'USD', '800001');
  usd = client.account;
  other = await createClient(a, 'bob', 'COP', '800002');
  cop = other.account;
  foreign = await createClient(b, 'foreign', 'USD', '800003');
});

afterAll(async () => { await app?.close(); });

test('publica la especificación OpenAPI y reporta sus dependencias activas', async () => {
  expect(data(await call('/health'))).toEqual({ status: 'up', postgres: 'up', redis: 'up' });
  const res = await fetch(`${await app.getUrl()}/api/docs-json`);
  expect(res.status).toBe(200);
  const spec = await res.json();
  const operation = spec.paths['/api/v1/transactions/transfer'].post;
  expect(operation.parameters).toEqual(expect.arrayContaining([
    expect.objectContaining({ name: 'Idempotency-Key', in: 'header', required: true }),
  ]));
  expect(operation.requestBody.content['application/json'].schema.required)
    .toContain('destination_account_number');
  const quote = spec.paths['/api/v1/transactions/quote'].get;
  expect(quote.parameters).toEqual(expect.arrayContaining([
    expect.objectContaining({ name: 'amount', in: 'query', required: true }),
  ]));
  expect(quote.responses[200].content['application/json'].schema.properties.data.properties.total_debit.type).toBe('string');
  expect(quote.responses[429].headers).toHaveProperty('Retry-After');
});

test('autenticación, JWT vencido, rotación, logout y roles', async () => {
  expect((await login(a.slug, a.email, 'incorrect')).status).toBe(401);
  expect((await login(a.slug, foreign.user.email)).status).toBe(401);
  expect((await login(`e2e-${marker}-unknown`, a.email)).status).toBe(401);
  expect((await call('/users', { token: client.token })).status).toBe(403);
  expect((await operation('deposit', a.token, { account_id: usd.id, amount: '1' })).status).toBe(403);
  const expired = await new SignJWT({ tenant_id: a.id, user_id: client.user.id, role: 'CLIENT', sid: randomUUID() })
    .setProtectedHeader({ alg: 'HS256' }).setIssuer('bankos').setAudience('bankos-api').setExpirationTime(1)
    .sign(Buffer.from(process.env.JWT_SECRET));
  expect((await call('/auth/me', { token: expired })).status).toBe(401);
  const session = await login(a.slug, client.user.email);
  expect(session.status).toBe(200);
  const oldRefresh = session.headers.getSetCookie().find(value => value.startsWith('bankos_refresh=')).split(';')[0];
  const refreshed = await call('/auth/refresh', { method: 'POST', headers: { Cookie: oldRefresh } });
  expect(refreshed.status).toBe(200);
  expect((await call('/auth/refresh', { method: 'POST', headers: { Cookie: oldRefresh } })).status).toBe(401);
  const newRefresh = refreshed.headers.getSetCookie().find(value => value.startsWith('bankos_refresh=')).split(';')[0];
  expect((await call('/auth/logout', { method: 'POST', headers: { Cookie: newRefresh } })).status).toBe(200);
  expect((await call('/auth/me', { token: refreshed.json.data.access_token })).status).toBe(401);

  const bearerSession = await login(a.slug, client.user.email);
  const bearer = data(bearerSession).access_token;
  const bearerRefresh = bearerSession.headers.getSetCookie().find(value => value.startsWith('bankos_refresh=')).split(';')[0];
  expect((await call('/auth/logout', { method: 'POST' })).status).toBe(401);
  expect((await call('/auth/logout', { method: 'POST', token: bearer })).status).toBe(200);
  expect((await call('/auth/me', { token: bearer })).status).toBe(401);
  expect((await call('/auth/refresh', { method: 'POST', headers: { Cookie: bearerRefresh } })).status).toBe(401);
});

test('aislamiento de usuarios, cuentas y RLS; titularidad de cliente', async () => {
  expect((await call(`/users/${foreign.user.id}`, { token: a.token })).status).toBe(404);
  expect((await call(`/accounts/${foreign.account.id}`, { token: a.token })).status).toBe(404);
  expect((await call(`/accounts/${foreign.account.id}/status`, {
    token: a.token, body: { status: 'BLOCKED' }, method: 'PATCH',
  })).status).toBe(404);
  expect((await call(`/accounts/${cop.id}`, { token: client.token })).status).toBe(404);
  expect((await call(`/accounts/${randomUUID()}`, { token: a.token })).status).toBe(404);
  const blocked = await operation('transfer', client.token, {
    source_account_id: usd.id, destination_account_number: foreign.account.number, amount: '1',
  });
  expect(blocked.status).toBe(404);
  expect(await db.tenant(a.id, tx => tx.rows('SELECT id FROM accounts WHERE tenant_id=$1', b.id))).toEqual([]);
  expect(await db.connection().rows('SELECT id FROM accounts')).toEqual([]);
});

test('depósitos, retiros, saldo insuficiente y bloqueo', async () => {
  data(await operation('deposit', client.token, { account_id: usd.id, amount: '100.00' }), 201);
  data(await operation('withdraw', client.token, { account_id: usd.id, amount: '10' }), 201);
  const insufficient = await operation('withdraw', client.token, { account_id: usd.id, amount: '100' });
  expect(insufficient.json.code).toBe('INSUFFICIENT_FUNDS');
  expect(await balance(usd, client.token)).toBe('90.00');
  data(await call(`/accounts/${usd.id}/status`, { token: a.token, body: { status: 'BLOCKED' }, method: 'PATCH' }));
  expect((await operation('deposit', client.token, { account_id: usd.id, amount: '1' })).json.code).toBe('ACCOUNT_NOT_ACTIVE');
  data(await call(`/accounts/${usd.id}/status`, { token: a.token, body: { status: 'ACTIVE' }, method: 'PATCH' }));
});

test('transferencia multimoneda, comisión, repetición idéntica y persistencia tras reiniciar', async () => {
  const key = randomUUID();
  const body = { source_account_id: usd.id, destination_account_number: cop.number, amount: '25.00' };
  const quotePath = input => `/transactions/quote?${new URLSearchParams(input)}`;
  const quote = data(await call(quotePath(body), { token: client.token }));
  expect(quote).toMatchObject({
    original_amount: '25.00', fee: '1.38', total_debit: '26.38',
    converted_amount: '100000.00', source_currency: 'USD', destination_currency: 'COP',
    exchange_rate: '4000.0000000000', transaction_limit: '1000000.00',
  });
  expect((await call(quotePath(body), { token: a.token })).status).toBe(403);
  expect((await call(quotePath({ ...body, destination_account_number: foreign.account.number }), { token: client.token })).status).toBe(404);
  expect(await balance(usd, client.token)).toBe('90.00');
  expect(await balance(cop, other.token)).toBe('0.00');
  const confirmed = { ...body, expected_quote: quote };
  const stale = await operation('transfer', client.token, {
    ...confirmed, expected_quote: { ...quote, fee: '1.00' },
  });
  expect(stale.json.code).toBe('QUOTE_CHANGED');
  expect(await balance(usd, client.token)).toBe('90.00');
  const first = await operation('transfer', client.token, confirmed, key);
  expect(data(first, 201)).toMatchObject({
    original_amount: '25.00', converted_amount: '100000.00', exchange_rate: '4000.0000000000', fee: '1.38',
  });
  expect(first.json.data.created_at).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z$/);
  expect((await operation('transfer', client.token, confirmed, key)).text).toBe(first.text);
  expect((await operation('transfer', client.token, { ...body, amount: '26.00' }, key)).json.code).toBe('IDEMPOTENCY_MISMATCH');
  expect((await operation('deposit', other.token, { account_id: cop.id, amount: '1.00' }, key)).status).toBe(201);
  await app.close();
  await start();
  db = app.get(Database);
  expect((await operation('transfer', client.token, confirmed, key)).text).toBe(first.text);
  expect(await balance(usd, client.token)).toBe('63.62');
  expect(await balance(cop, other.token)).toBe('100001.00');
});

test('concurrencia no duplica débitos ni permite saldos negativos', async () => {
  const key = randomUUID();
  const body = { source_account_id: usd.id, destination_account_number: cop.number, amount: '40.00' };
  const responses = await Promise.all([
    operation('transfer', client.token, body, key),
    operation('transfer', client.token, body, key),
    operation('transfer', client.token, body),
  ]);
  const completed = responses.filter(result => result.status === 201);
  expect(completed.length).toBeGreaterThanOrEqual(1);
  expect(new Set(completed.map(result => result.json.data.id)).size).toBe(1);
  expect(responses.some(result => result.json.code === 'INSUFFICIENT_FUNDS')).toBe(true);
  expect(await balance(usd, client.token)).toBe('22.02');
  expect(await balance(cop, other.token)).toBe('260001.00');
});

test('auditoría inmutable, outbox persistente y reintentos independientes', async () => {
  const logs = data(await call('/audit', { token: a.token }));
  expect(logs.items.some(row => row.action === 'ACCOUNT_BLOCKED')).toBe(true);
  await expect(db.tenant(a.id, tx => tx.run('DELETE FROM audit_logs WHERE tenant_id=$1', a.id))).rejects.toThrow();
  await db.tenant(a.id, tx => tx.run(`INSERT INTO webhook_config (tenant_id,url,secret,timeout_ms)
    VALUES ($1,'https://example.com/', $2,500) ON CONFLICT DO NOTHING`, a.id, webhookSecret));

  const confirmed = data(await operation('transfer', client.token, {
    source_account_id: usd.id, destination_account_number: cop.number, amount: '1.00',
  }), 201);
  const event = await db.tenant(a.id, tx => tx.one(
    "SELECT id FROM outbox_events WHERE tenant_id=$1 AND payload->'data'->>'id'=$2 AND state='PENDING'", a.id, confirmed.id));
  expect(event).toBeDefined();
  const send = jest.fn().mockResolvedValueOnce(503).mockResolvedValueOnce(204);
  const worker = new OutboxWorker(db, send);
  await worker.tick();
  await db.tenant(a.id, tx => tx.run('UPDATE outbox_events SET next_attempt_at=now() WHERE tenant_id=$1 AND id=$2', a.id, event.id));
  await worker.tick();
  expect(send.mock.calls[0][2]).toMatchObject({ 'x-bankos-event-id': event.id, 'x-correlation-id': 'bankos-integration' });
  const attempts = await db.tenant(a.id, tx => tx.rows(
    'SELECT http_status FROM webhook_deliveries WHERE tenant_id=$1 AND event_id=$2 ORDER BY attempt', a.id, event.id));
  expect(attempts.map(row => row.http_status)).toEqual([503, 204]);
  expect(await balance(usd, client.token)).toBe('20.00');
});

test('revierte el débito si el abono excede el rango de saldo', async () => {
  const initial = await balance(usd, client.token);
  await db.tenant(a.id, tx => tx.run("UPDATE accounts SET balance='999999999999999999.99' WHERE tenant_id=$1 AND id=$2", a.id, cop.id));
  const rejected = await operation('transfer', client.token, {
    source_account_id: usd.id, destination_account_number: cop.number, amount: '1.00',
  });
  expect(rejected.status).toBe(422);
  expect(rejected.json.code).toBe('AMOUNT_OUT_OF_RANGE');
  expect(await balance(usd, client.token)).toBe(initial);
  expect(await balance(cop, other.token)).toBe('999999999999999999.99');
});

test('el límite por tenant es independiente y devuelve Retry-After', async () => {
  const redis = app.get(REDIS);
  const bucket = `bankos:rate:tenant:${a.id}`;
  const limit = Number(process.env.RATE_LIMIT_TENANT ?? 400);
  await redis.set(bucket, limit, 'EX', 30);
  try {
    const limited = await call('/auth/me', { token: client.token });
    expect(limited.status).toBe(429);
    expect(limited.json.code).toBe('RATE_LIMIT_EXCEEDED');
    expect(Number(limited.headers.get('Retry-After'))).toBeGreaterThan(0);
    expect(Number(limited.headers.get('Retry-After'))).toBeLessThanOrEqual(30);
    expect((await call('/auth/me', { token: other.token })).status).toBe(429);
    expect((await call('/auth/me', { token: foreign.token })).status).toBe(200);
  } finally {
    await redis.del(bucket);
  }
});

test('el límite de inicio de sesión usa la cuenta normalizada y el tenant', async () => {
  const redis = app.get(REDIS);
  const account = createHash('sha256').update(JSON.stringify([a.slug, a.email])).digest('hex');
  const bucket = `bankos:rate:login-account:${account}`;
  const limit = Number(process.env.RATE_LIMIT_LOGIN_ACCOUNT ?? 10);
  await redis.set(bucket, limit, 'EX', 30);
  try {
    const limited = await login(a.slug.toUpperCase(), a.email.toUpperCase());
    expect(limited.status).toBe(429);
    expect(limited.json.code).toBe('RATE_LIMIT_EXCEEDED');
    expect(Number(limited.headers.get('Retry-After'))).toBeGreaterThan(0);
    expect((await login(b.slug, b.email)).status).toBe(200);
  } finally {
    await redis.del(bucket);
  }
});

test('el superadmin usa usuario y contraseña para crear un banco', async () => {
  await app.get(REDIS).del('bankos:rate:auth:127.0.0.1');
  const credentials = { username: process.env.PLATFORM_ADMIN_USERNAME, password: process.env.PLATFORM_ADMIN_PASSWORD };
  expect((await call('/tenants/platform-login', { body: { ...credentials, password: 'incorrecta' } })).status).toBe(401);
  const { access_token: token } = data(await call('/tenants/platform-login', { body: credentials }));
  const slug = `e2e-${marker}-platform`;
  const body = { slug, name: slug, currency: 'COP', transaction_limit: '1000', fee_fixed: '0', fee_percent: '0',
    admin: { first_name: 'Test', last_name: 'Admin', email: 'platform-bank@example.test', password } };
  expect((await call('/tenants', { token: a.token, body })).status).toBe(403);
  expect(data(await call('/tenants', { token, body }), 201).admin.role).toBe('ADMIN');
  expect((await call('/accounts', { token })).status).toBe(401);
});

test('autorregistro crea una sola cuenta en el banco elegido y respeta su aislamiento', async () => {
  const bank = await provision('registration');
  const directory = data(await call('/tenants/directory?limit=100'));
  expect(directory.items).toContainEqual({ slug: bank.slug, name: bank.slug });

  const input = { tenant_slug: bank.slug, first_name: 'New', last_name: 'Client',
    email: 'self-register@example.test', password };
  expect((await call('/auth/self-register', { body: { ...input, role: 'ADMIN' } })).status).toBe(400);
  const { user, account } = data(await call('/auth/self-register', { body: input }), 201);
  expect(user).toMatchObject({ role: 'CLIENT', tenant_id: bank.id });
  expect(account).toMatchObject({ owner_id: user.id, tenant_id: bank.id, currency: 'COP',
    balance: '0.00', status: 'ACTIVE' });
  expect((await call('/auth/self-register', { body: input })).status).toBe(409);
  const token = data(await login(bank.slug, input.email)).access_token;
  expect(data(await call('/accounts', { token })).items).toEqual([account]);
  expect((await call('/tenants/config', { token })).status).toBe(403);
  expect((await login(a.slug, input.email)).status).toBe(401);
  expect((await call(`/accounts/${account.id}`, { token: a.token })).status).toBe(404);

  data(await call(`/tenants/${bank.id}/status`, {
    method: 'PATCH', headers: { 'X-Platform-Key': process.env.PLATFORM_ADMIN_KEY }, body: { active: false },
  }));
  expect(data(await call('/tenants/directory?limit=100')).items).not.toContainEqual({ slug: bank.slug, name: bank.slug });
  expect((await call('/auth/self-register', { body: { ...input, email: 'another@example.test' } })).status).toBe(404);
});
