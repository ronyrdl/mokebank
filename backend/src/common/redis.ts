import { Redis } from 'ioredis';
import { required } from './config.js';

export function openRedis() {
  return new Redis(required('REDIS_URL'), {
    lazyConnect: true,
    enableOfflineQueue: false,
    maxRetriesPerRequest: 0,
    commandTimeout: 3000,
  });
}

export const REDIS = Symbol('BANKOS_REDIS');
