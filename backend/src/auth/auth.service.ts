import { createHash, randomBytes, randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { jwtVerify, SignJWT } from 'jose';
import { Database, type DbSession } from '../database/database.js';
import { required, integerSetting } from '../common/config.js';
import { unauthorized } from '../common/errors.js';
import { uuid, type loginInput } from '../common/schemas.js';
import { userFields, type Identity, type User } from '../common/types.js';
import type { z } from 'zod';

type Credential = User & { password_hash: string };
type TokenRow = { id: string; user_id: string };
const issuer = 'bankos';
const audience = 'bankos-api';
const dummyHash = bcrypt.hashSync('bankos-invalid-account', 12);
const digest = (value: string) => createHash('sha256').update(value).digest('hex');

export class AuthService {
  private readonly secret = Buffer.from(required('JWT_SECRET', 32));
  readonly accessSeconds = integerSetting('ACCESS_TOKEN_SECONDS', 900);
  readonly refreshSeconds = integerSetting('REFRESH_TOKEN_SECONDS', 604800);

  constructor(private readonly db: Database) {}

  async login(input: z.infer<typeof loginInput>) {
    const tenant = await this.db.connection().one<{ id: string | null }>('SELECT lookup_tenant($1) AS id', input.tenant_slug);
    const id = tenant?.id;
    if (!id) {
      await bcrypt.compare(input.password, dummyHash);
      unauthorized();
    }

    return this.db.tenant(id, async tx => {
      const user = await tx.one<Credential>(
        `SELECT ${userFields},password_hash FROM users WHERE tenant_id=$1 AND email=$2`, id, input.email);
      const match = await bcrypt.compare(input.password, user?.password_hash ?? dummyHash);
      if (!user?.active || !match || Buffer.byteLength(input.password) > 72) unauthorized();
      const { password_hash: _, ...profile } = user;
      return this.issue(tx, profile);
    });
  }

  private async issue(tx: DbSession, user: User) {
    const sid = randomUUID();
    const refresh = `${user.tenant_id}.${randomBytes(32).toString('base64url')}`;
    await tx.run(`INSERT INTO refresh_tokens (tenant_id,id,user_id,token_hash,expires_at)
      VALUES ($1,$2,$3,$4,now()+$5*interval '1 second')`,
      user.tenant_id, sid, user.id, digest(refresh), this.refreshSeconds);
    const access = await new SignJWT({ tenant_id: user.tenant_id, user_id: user.id, role: user.role, sid })
      .setProtectedHeader({ alg: 'HS256' }).setIssuer(issuer).setAudience(audience)
      .setIssuedAt().setExpirationTime(`${this.accessSeconds}s`).sign(this.secret);
    return { user, access, refresh };
  }

  private async accessClaims(token: string | undefined) {
    if (!token) unauthorized();
    let claims;
    try {
      ({ payload: claims } = await jwtVerify(token, this.secret, { issuer, audience, algorithms: ['HS256'] }));
    } catch {
      unauthorized();
    }
    const tenant = uuid.safeParse(claims.tenant_id);
    const user = uuid.safeParse(claims.user_id);
    const sid = uuid.safeParse(claims.sid);
    if (!tenant.success || !user.success || !sid.success) unauthorized();
    return { tenant: tenant.data, user: user.data, sid: sid.data, role: claims.role };
  }

  async authenticate(token: string | undefined): Promise<Identity> {
    const { tenant, user, sid, role } = await this.accessClaims(token);
    const identity = await this.db.tenant(tenant, tx => tx.one<Identity>(
      `SELECT u.tenant_id,u.id AS user_id,u.role FROM users u
        JOIN tenants t ON t.id=u.tenant_id
        JOIN refresh_tokens r ON r.tenant_id=u.tenant_id AND r.user_id=u.id
        WHERE u.tenant_id=$1 AND u.id=$2 AND r.id=$3 AND r.revoked_at IS NULL
        AND r.expires_at>now() AND t.active AND u.active`,
      tenant, user, sid));
    if (!identity || identity.role !== role) unauthorized();
    return identity;
  }

  refresh(token: string | undefined) {
    const id = this.refreshTenant(token);
    if (!id || !token) unauthorized();
    return this.db.tenant(id, async tx => {
      const row = await this.validRefresh(tx, id, token);
      if (!row) unauthorized();
      const user = await tx.one<User>(
        `SELECT ${userFields} FROM users WHERE tenant_id=$1 AND id=$2 AND active
         AND EXISTS(SELECT 1 FROM tenants WHERE id=$1 AND active)`, id, row.user_id);
      if (!user) unauthorized();
      await tx.run('UPDATE refresh_tokens SET revoked_at=now() WHERE tenant_id=$1 AND id=$2', id, row.id);
      return this.issue(tx, user);
    });
  }

  async logout(token: string | undefined, bearer: string | undefined) {
    const id = this.refreshTenant(token);
    if (id && token) {
      const revoked = await this.db.tenant(id, tx => tx.one(
        `UPDATE refresh_tokens SET revoked_at=now() WHERE tenant_id=$1 AND token_hash=$2
         AND revoked_at IS NULL AND expires_at>now() RETURNING id`, id, digest(token)));
      if (revoked) return;
    }
    const { tenant, user, sid } = await this.accessClaims(bearer);
    const revoked = await this.db.tenant(tenant, tx => tx.one(
      `UPDATE refresh_tokens SET revoked_at=now() WHERE tenant_id=$1 AND user_id=$2 AND id=$3
       AND revoked_at IS NULL AND expires_at>now() RETURNING id`, tenant, user, sid));
    if (!revoked) unauthorized();
  }

  me(identity: Identity) {
    return this.db.tenant(identity.tenant_id, tx => tx.one<User>(
      `SELECT ${userFields} FROM users WHERE tenant_id=$1 AND id=$2 AND active`, identity.tenant_id, identity.user_id));
  }

  private refreshTenant(token: string | undefined): string | undefined {
    if (!token || !/^[\da-f-]{36}\.[A-Za-z0-9_-]{43}$/i.test(token)) return;
    const result = uuid.safeParse(token.split('.')[0]);
    return result.success ? result.data : undefined;
  }

  private validRefresh(tx: DbSession, tenant: string, token: string) {
    return tx.one<TokenRow>(
      `SELECT id,user_id FROM refresh_tokens WHERE tenant_id=$1 AND token_hash=$2
       AND revoked_at IS NULL AND expires_at>now() FOR UPDATE`, tenant, digest(token));
  }
}
