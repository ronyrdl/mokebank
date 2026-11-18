import { randomUUID, timingSafeEqual, createHash, createHmac } from 'node:crypto';
import { jwtVerify, SignJWT } from 'jose';
import type { z } from 'zod';
import type { Database, DbSession } from '../database/database.js';
import { required } from '../common/config.js';
import { forbidden, notFound, unauthorized } from '../common/errors.js';
import type { Identity, Trace } from '../common/types.js';
import { pagination, type pageSchema, type platformLoginInput, type settingsPatch, type tenantInput } from '../common/schemas.js';
import { audit } from '../audit/audit.service.js';
import { insertUser } from '../users/users.service.js';
import { readRates, writeRates } from '../currencies/currencies.service.js';
import { publicWebhook, readWebhook, writeWebhook } from '../webhooks/webhooks.service.js';
import { resolveEndpoint } from '../webhooks/endpoint.js';

export type TenantConfig = {
  id: string; slug: string; name: string; active: boolean;
  currency: string; transaction_limit: string; fee_fixed: string; fee_percent: string;
};

async function readConfig(tx: DbSession, tenant: string) {
  const config = await tx.one<TenantConfig>(`SELECT t.id,t.slug,t.name,t.active,
    c.currency,c.transaction_limit,c.fee_fixed,c.fee_percent FROM tenants t
    JOIN tenant_config c ON c.tenant_id=t.id WHERE t.id=$1`, tenant);
  if (!config) notFound('Institución no encontrada');
  return { ...config, rates: await readRates(tx, tenant), webhook: publicWebhook(await readWebhook(tx, tenant)) };
}

const platformAudience = 'bankos-platform';
const platformSessionSeconds = 900;
const hash = (value: string) => createHash('sha256').update(value).digest();

type PlatformAccess = { key?: string; bearer?: string };

export class TenantsService {
  private readonly platformKey = required('PLATFORM_ADMIN_KEY', 32);

  private readonly username = process.env.PLATFORM_ADMIN_USERNAME ?? '';
  private readonly password = process.env.PLATFORM_ADMIN_PASSWORD ?? '';
  private readonly signingKey = createHmac('sha256', this.platformKey)
    .update(JSON.stringify([platformAudience, this.username, this.password])).digest();

  constructor(private readonly db: Database) {}

  async platformLogin(input: z.infer<typeof platformLoginInput>) {
    const usernameMatches = timingSafeEqual(hash(input.username), hash(this.username));
    const passwordMatches = timingSafeEqual(hash(input.password), hash(this.password));
    if (!this.username || this.password.length < 12 || !usernameMatches || !passwordMatches) unauthorized();
    const access = await new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer('bankos').setAudience(platformAudience).setSubject(this.username)
      .setIssuedAt().setExpirationTime(`${platformSessionSeconds}s`).sign(this.signingKey);
    return { access_token: access, token_type: 'Bearer', expires_in: platformSessionSeconds };
  }

  private async authorizePlatform({ key, bearer }: PlatformAccess) {
    if (key && timingSafeEqual(hash(key), hash(this.platformKey))) return;
    if (!bearer || !this.username || this.password.length < 12) forbidden();
    try {
      await jwtVerify(bearer, this.signingKey, {
        issuer: 'bankos', audience: platformAudience, subject: this.username,
        algorithms: ['HS256'], requiredClaims: ['exp'],
      });
    } catch {
      forbidden();
    }
  }

  async directory(input: z.infer<typeof pageSchema>) {
    const { page, limit, offset } = pagination(input);
    const rows = await this.db.connection().rows<{ slug: string; name: string }>(
      'SELECT slug,name FROM active_tenant_directory($1,$2) ORDER BY slug', limit + 1, offset);
    return { items: rows.slice(0, limit), page, limit, has_more: rows.length > limit };
  }

  async create(access: PlatformAccess, trace: Trace, input: z.infer<typeof tenantInput>) {
    await this.authorizePlatform(access);
    if (input.webhook) await resolveEndpoint(input.webhook.url);
    const tenant = randomUUID();
    return this.db.tenant(tenant, async tx => {
      await tx.run('INSERT INTO tenants (id,slug,name) VALUES ($1,$2,$3)', tenant, input.slug, input.name);
      await tx.run(`INSERT INTO tenant_config (tenant_id,currency,transaction_limit,fee_fixed,fee_percent)
        VALUES ($1,$2,$3,$4,$5)`, tenant, input.currency, input.transaction_limit, input.fee_fixed, input.fee_percent);
      const admin = await insertUser(tx, tenant, input.admin, 'ADMIN');
      await writeRates(tx, tenant, input.rates ?? []);
      if (input.webhook) await writeWebhook(tx, tenant, input.webhook);
      const config = await readConfig(tx, tenant);
      await audit(tx, { tenant_id: tenant, user_id: admin.id, role: 'ADMIN' }, trace, 'TENANT_PROVISIONED', tenant,
        null, { ...config, actor_type: 'PLATFORM' });
      return { ...config, admin };
    });
  }

  get(actor: Identity) {
    return this.db.tenant(actor.tenant_id, tx => readConfig(tx, actor.tenant_id));
  }

  async update(actor: Identity, trace: Trace, input: z.infer<typeof settingsPatch>) {
    if (input.webhook) await resolveEndpoint(input.webhook.url);
    const tenant = actor.tenant_id;
    return this.db.tenant(tenant, async tx => {
      await tx.run('SELECT id FROM tenants WHERE id=$1 FOR UPDATE', tenant);
      await tx.run('SELECT tenant_id FROM tenant_config WHERE tenant_id=$1 FOR UPDATE', tenant);
      const previous = await readConfig(tx, tenant);
      if (!previous.active) forbidden();
      await tx.run('UPDATE tenants SET active=$2 WHERE id=$1', tenant, input.active ?? previous.active);
      await tx.run(`UPDATE tenant_config SET currency=$2,transaction_limit=$3,fee_fixed=$4,fee_percent=$5 WHERE tenant_id=$1`,
        tenant, input.currency ?? previous.currency, input.transaction_limit ?? previous.transaction_limit,
        input.fee_fixed ?? previous.fee_fixed, input.fee_percent ?? previous.fee_percent);
      if (input.rates) await writeRates(tx, tenant, input.rates);
      if (input.webhook) await writeWebhook(tx, tenant, input.webhook);
      const next = await readConfig(tx, tenant);
      await audit(tx, actor, trace, 'TENANT_CONFIG_CHANGED', tenant, previous, next);
      return next;
    });
  }

  async setStatus(access: PlatformAccess, trace: Trace, tenant: string, active: boolean) {
    await this.authorizePlatform(access);
    return this.db.tenant(tenant, async tx => {
      const previous = await tx.one<{ active: boolean }>('SELECT active FROM tenants WHERE id=$1 FOR UPDATE', tenant);
      if (!previous) notFound('Institución no encontrada');
      const admin = await tx.one<{ id: string }>("SELECT id FROM users WHERE tenant_id=$1 AND role='ADMIN' LIMIT 1", tenant);
      if (!admin) notFound('Administrador no encontrado');
      await tx.run('UPDATE tenants SET active=$2 WHERE id=$1', tenant, active);
      await audit(tx, { tenant_id: tenant, user_id: admin.id, role: 'ADMIN' }, trace, 'PLATFORM_TENANT_STATUS_CHANGED',
        tenant, previous, { active, actor_type: 'PLATFORM' });
      return { id: tenant, active };
    });
  }
}
