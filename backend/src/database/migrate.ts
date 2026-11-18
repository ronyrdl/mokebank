import { readdir, readFile } from 'node:fs/promises';
import pg from 'pg';

const connectionString = process.env.MIGRATION_DATABASE_URL;
if (!connectionString) throw new Error('MIGRATION_DATABASE_URL is required');
const client = new pg.Client({ connectionString });
await client.connect();

async function provisionApplicationRole(password: string) {
  const existing = await client.query("SELECT 1 FROM pg_roles WHERE rolname = 'bankos_app'");
  if (!existing.rowCount) {
    const { rows } = await client.query<{ statement: string }>(
      `SELECT format('CREATE ROLE bankos_app LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE',
        $1::text) AS statement`,
      [password],
    );
    await client.query(rows[0].statement);
  }
  await client.query('REVOKE CREATE ON SCHEMA public FROM PUBLIC');
}

try {
  await client.query('BEGIN');
  await client.query('SELECT pg_advisory_xact_lock(78124001)');
  if (process.env.APP_DB_PASSWORD) {
    await provisionApplicationRole(process.env.APP_DB_PASSWORD);
  }
  await client.query('CREATE TABLE IF NOT EXISTS bankos_migrations (name text PRIMARY KEY, executed_at timestamptz NOT NULL DEFAULT now())');
  const folder = new URL('../../migrations/', import.meta.url);
  for (const name of (await readdir(folder)).filter(name => /^\d+.*\.sql$/.test(name)).sort()) {
    const { rowCount } = await client.query('SELECT 1 FROM bankos_migrations WHERE name=$1', [name]);
    if (rowCount) continue;
    await client.query(await readFile(new URL(name, folder), 'utf8'));
    await client.query('INSERT INTO bankos_migrations (name) VALUES ($1)', [name]);
    console.log(`Applied ${name}`);
  }
  await client.query('COMMIT');
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  await client.end();
}
