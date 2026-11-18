import { randomUUID } from 'node:crypto';
import { Database } from './database.js';
import { required } from '../common/config.js';
import { TenantsService } from '../tenants/tenants.service.js';
import { UsersService } from '../users/users.service.js';
import { AccountsService } from '../accounts/accounts.service.js';
import type { Identity } from '../common/types.js';

if (process.env.ALLOW_DEMO_SEED !== 'true') throw new Error('Set ALLOW_DEMO_SEED=true to install demo data');
const password = process.env.DEMO_PASSWORD ?? 'BankOS-demo-2026!';
const db = await Database.open();

try {
  const tenants = new TenantsService(db);
  const users = new UsersService(db);
  const accounts = new AccountsService(db);
  for (const [slug, name, suffix] of [['demo-a', 'Banco Demo A', '1'], ['demo-b', 'Banco Demo B', '2']]) {
    const trace = { correlationId: randomUUID(), ip: 'seed' };
    const existing = await db.connection().one<{ id: string | null }>('SELECT lookup_tenant($1) AS id', slug);
    let actor: Identity;
    if (existing?.id) {
      const id = existing.id;
      const admin = await db.tenant(id, tx => tx.one<{ id: string }>(
        "SELECT id FROM users WHERE tenant_id=$1 AND email=$2 AND role='ADMIN'", id, `admin@${slug}.example`));
      if (!admin) throw new Error(`Demo tenant slug is already in use: ${slug}`);
      actor = { tenant_id: id, user_id: admin.id, role: 'ADMIN' };
    } else {
      const bank = await tenants.create({ key: required('PLATFORM_ADMIN_KEY', 32) }, trace, {
        name, slug, currency: 'COP', transaction_limit: '50000000.00', fee_fixed: '1.00', fee_percent: '1.50',
        admin: { first_name: 'Admin', last_name: 'Demo', email: `admin@${slug}.example`, password },
        rates: [
          { source_currency: 'USD', destination_currency: 'COP', rate: '4000' },
          { source_currency: 'COP', destination_currency: 'USD', rate: '0.00025' },
          { source_currency: 'EUR', destination_currency: 'COP', rate: '4300' },
        ],
      });
      actor = { tenant_id: bank.id, user_id: bank.admin.id, role: 'ADMIN' };
    }

    for (const [index, currency] of [['01', 'USD'], ['02', 'COP']] as const) {
      const email = `cliente${index}@${slug}.example`;
      const previous = await db.tenant(actor.tenant_id, tx => tx.one<{ id: string }>(
        'SELECT id FROM users WHERE tenant_id=$1 AND email=$2', actor.tenant_id, email));
      const client = previous ?? await users.create(actor, trace, { first_name: 'Cliente', last_name: index, email, password });
      const number = `900000${suffix}${index}`;
      const account = await db.tenant(actor.tenant_id, tx => tx.one(
        'SELECT id FROM accounts WHERE tenant_id=$1 AND number=$2', actor.tenant_id, number));
      if (!account) await accounts.create(actor, trace, { owner_id: client.id, currency, number });
    }
  }
  console.log('Demo tenants ready: demo-a, demo-b');
} finally {
  await db.close();
}
