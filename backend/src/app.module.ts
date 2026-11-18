import { Global, Module } from '@nestjs/common';
import { Redis } from 'ioredis';
import { Database } from './database/database.js';
import { openRedis, REDIS } from './common/redis.js';
import { AuthController } from './auth/auth.controller.js';
import { AuthService } from './auth/auth.service.js';
import { TenantsController } from './tenants/tenants.controller.js';
import { TenantsService } from './tenants/tenants.service.js';
import { UsersController } from './users/users.controller.js';
import { UsersService } from './users/users.service.js';
import { AccountsController } from './accounts/accounts.controller.js';
import { AccountsService } from './accounts/accounts.service.js';
import { TransactionsController } from './transactions/transactions.controller.js';
import { TransactionsService } from './transactions/transactions.service.js';
import { CurrenciesController } from './currencies/currencies.controller.js';
import { CurrenciesService } from './currencies/currencies.service.js';
import { WebhooksController } from './webhooks/webhooks.controller.js';
import { WebhooksService } from './webhooks/webhooks.service.js';
import { IdempotencyService } from './idempotency/idempotency.service.js';
import { AuditController } from './audit/audit.controller.js';
import { AuditService } from './audit/audit.service.js';
import { HealthController } from './health/health.controller.js';

@Global()
@Module({
  providers: [
    { provide: Database, useFactory: () => Database.open() },
    { provide: REDIS, useFactory: async () => {
      const redis = openRedis();
      redis.on('error', () => console.error(JSON.stringify({ message: 'redis.connection_error' })));
      await redis.connect();
      Object.assign(redis, { onApplicationShutdown: () => redis.disconnect() });
      return redis;
    } },
  ],
  exports: [Database, REDIS],
})
class InfrastructureModule {}

@Module({
  controllers: [UsersController],
  providers: [{ provide: UsersService, inject: [Database], useFactory: (db: Database) => new UsersService(db) }],
  exports: [UsersService],
})
class UsersModule {}

@Module({
  imports: [UsersModule],
  controllers: [AuthController],
  providers: [{ provide: AuthService, inject: [Database], useFactory: (db: Database) => new AuthService(db) }],
  exports: [AuthService],
})
class AuthModule {}

@Module({
  controllers: [TenantsController],
  providers: [{ provide: TenantsService, inject: [Database], useFactory: (db: Database) => new TenantsService(db) }],
})
class TenantsModule {}

@Module({
  providers: [{ provide: IdempotencyService, inject: [Database, REDIS],
    useFactory: (db: Database, redis: Redis) => new IdempotencyService(db, redis) }],
  exports: [IdempotencyService],
})
class IdempotencyModule {}

@Module({
  imports: [IdempotencyModule],
  controllers: [TransactionsController],
  providers: [{ provide: TransactionsService, inject: [Database, IdempotencyService],
    useFactory: (db: Database, idempotency: IdempotencyService) => new TransactionsService(db, idempotency) }],
  exports: [TransactionsService],
})
class TransactionsModule {}

@Module({
  imports: [TransactionsModule],
  controllers: [AccountsController],
  providers: [{ provide: AccountsService, inject: [Database], useFactory: (db: Database) => new AccountsService(db) }],
})
class AccountsModule {}

@Module({
  controllers: [CurrenciesController],
  providers: [{ provide: CurrenciesService, inject: [Database], useFactory: (db: Database) => new CurrenciesService(db) }],
})
class CurrenciesModule {}

@Module({
  controllers: [WebhooksController],
  providers: [{ provide: WebhooksService, inject: [Database], useFactory: (db: Database) => new WebhooksService(db) }],
})
class WebhooksModule {}

@Module({
  controllers: [AuditController],
  providers: [{ provide: AuditService, inject: [Database], useFactory: (db: Database) => new AuditService(db) }],
})
class AuditModule {}

@Module({
  imports: [InfrastructureModule, TenantsModule, UsersModule, AuthModule, AccountsModule, TransactionsModule,
    CurrenciesModule, WebhooksModule, AuditModule],
  controllers: [HealthController],
})
export class AppModule {}
