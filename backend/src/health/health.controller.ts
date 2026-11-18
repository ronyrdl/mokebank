import { Controller, Get, Inject } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { Redis } from 'ioredis';
import { Database } from '../database/database.js';
import { Contract } from '../common/http.js';
import { healthResponse } from '../common/response-schemas.js';
import { REDIS } from '../common/redis.js';
import { BankError } from '../common/errors.js';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly db: Database, @Inject(REDIS) private readonly redis: Redis) {}

  @Get()
  @Contract({ response: healthResponse, access: 'public' })
  async health() {
    try {
      await Promise.all([this.db.connection().run('SELECT 1'), this.redis.ping()]);
      return { status: 'up', postgres: 'up', redis: 'up' };
    } catch {
      throw new BankError(503, 'DEPENDENCY_UNAVAILABLE', 'Una dependencia no está disponible');
    }
  }
}
