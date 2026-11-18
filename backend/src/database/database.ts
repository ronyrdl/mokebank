import type { MikroORM as CoreMikroORM } from '@mikro-orm/core';
import { MikroORM, type EntityManager, type PostgreSqlDriver } from '@mikro-orm/postgresql';
import { CompiledQuery } from 'kysely';
import pg from 'pg';
import { entities } from './entities.js';

function timestampToRfc3339(value: string): string {
  const date: Date = pg.types.getTypeParser(pg.types.builtins.TIMESTAMPTZ)(value);
  const extraDigits = /\.(\d{3})(\d+)[+-]/.exec(value)?.[2] ?? '';
  return date.toISOString().replace(/Z$/, `${extraDigits}Z`);
}

export class DbSession {
  constructor(private readonly em: EntityManager) {}

  async rows<T>(sql: string, ...params: unknown[]): Promise<T[]> {
    const result = await this.em.getKysely().executeQuery<T>(CompiledQuery.raw(sql, params));
    return result.rows;
  }

  async one<T>(sql: string, ...params: unknown[]): Promise<T | undefined> {
    return (await this.rows<T>(sql, ...params))[0];
  }

  async run(sql: string, ...params: unknown[]): Promise<void> {
    await this.rows(sql, ...params);
  }

  atomic<T>(operation: (db: DbSession) => Promise<T>): Promise<T> {
    return this.em.transactional(em => operation(new DbSession(em)), { propagation: 'nested' });
  }
}

export class Database {
  private constructor(private readonly orm: CoreMikroORM<PostgreSqlDriver, EntityManager>) {}

  static async open(url = process.env.DATABASE_URL): Promise<Database> {
    if (!url) throw new Error('DATABASE_URL is required');
    const orm = await MikroORM.init<PostgreSqlDriver, EntityManager>({
      clientUrl: url,
      entities,
      forceUtcTimezone: true,
      driverOptions: {
        onPoolCreated(pool: pg.Pool) {
          (pool.options.types as pg.TypeOverrides).setTypeParser(pg.types.builtins.TIMESTAMPTZ, timestampToRfc3339);
        },
      },
    });
    await orm.connect();
    return new Database(orm);
  }

  async tenant<T>(id: string, operation: (db: DbSession) => Promise<T>): Promise<T> {
    return this.orm.em.fork().transactional(async em => {
      const db = new DbSession(em);
      await db.run("SELECT set_config('bankos.tenant_id', $1, true)", id);
      return operation(db);
    });
  }

  connection(): DbSession {
    return new DbSession(this.orm.em.fork());
  }

  close(): Promise<void> {
    return this.orm.close(true);
  }

  onApplicationShutdown(): Promise<void> {
    return this.close();
  }
}
