import { createHash, randomUUID } from 'node:crypto';
import {
  applyDecorators, Catch, HttpException, SetMetadata,
  type ArgumentsHost, type CallHandler, type CanActivate, type ExecutionContext, type ExceptionFilter, type NestInterceptor,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiBody, ApiCookieAuth, ApiBearerAuth, ApiHeader, ApiParam, ApiQuery, ApiResponse, type ApiBodyOptions } from '@nestjs/swagger';
import type { Response, NextFunction } from 'express';
import type { Redis } from 'ioredis';
import { map } from 'rxjs';
import { z } from 'zod';
import type { AuthService } from '../auth/auth.service.js';
import { integerSetting } from './config.js';
import { BankError, forbidden } from './errors.js';
import { failure, success } from './response.js';
import type { BankRequest } from './types.js';
import { loginInput, uuid } from './schemas.js';

const CONTRACT = Symbol('BANKOS_CONTRACT');
export const ACCESS_COOKIE = 'bankos_access';
export const REFRESH_COOKIE = 'bankos_refresh';

interface ContractOptions {
  body?: z.ZodType;
  query?: z.ZodType;
  response: z.ZodType;
  access?: 'public' | 'platform' | 'admin' | 'client' | 'user';
  example?: Record<string, unknown>;
  id?: boolean;
  refreshCookie?: boolean;
  bearer?: boolean;
  limit?: 'auth' | 'login' | 'money';
  status?: number;
}

const responseSchema = {
  type: 'object',
  required: ['success', 'code', 'message', 'data', 'meta'],
  properties: {
    success: { type: 'boolean', example: true },
    code: { type: 'string', example: 'OK' },
    message: { type: 'string', example: 'Operación realizada correctamente' },
    meta: { type: 'object', required: ['correlationId'], properties: { correlationId: { type: 'string' } } },
  },
};

export function Contract(options: ContractOptions) {
  const access = options.access ?? 'user';
  const accessDescription = access === 'admin' ? 'Requiere rol ADMIN'
    : access === 'client' ? 'Requiere rol CLIENT' : 'Respuesta exitosa';
  const dataSchema = z.toJSONSchema(options.response, { target: 'openapi-3.0' }) as
    Extract<ApiBodyOptions, { schema: unknown }>['schema'];
  const decorators: Parameters<typeof applyDecorators> = [
    SetMetadata(CONTRACT, options),
    ApiHeader({ name: 'X-Correlation-ID', required: false, description: 'Identificador de trazabilidad' }),
    ApiResponse({ status: options.status ?? 200, description: accessDescription, schema: {
      ...responseSchema, properties: {
        ...responseSchema.properties, data: dataSchema,
      },
    } }),
  ];
  for (const status of [400, 401, 403, 404, 409, 422, 429, 503]) {
    decorators.push(ApiResponse({ status, description: 'Respuesta de error',
      ...(status === 429 && { headers: { 'Retry-After': {
        description: 'Segundos hasta que se reinicie el contador', schema: { type: 'integer', minimum: 1 },
      } } }),
      schema: {
        example: { success: false, code: 'ERROR_CODE', message: 'Descripción del error', details: {}, meta: { correlationId: 'uuid' } },
      },
    }));
  }
  if (options.body) {
    const schema = z.toJSONSchema(options.body, { io: 'input', target: 'openapi-3.0' });
    const examples = options.example ? { solicitud: { value: options.example } } : undefined;
    const body = { schema, examples } as Parameters<typeof ApiBody>[0];
    decorators.push(ApiBody(body));
  }
  if (options.query) {
    const schema = z.toJSONSchema(options.query, { io: 'input', target: 'openapi-3.0' });
    const properties = (schema.properties ?? {}) as Record<string, { type?: string }>;
    for (const [name, property] of Object.entries(properties)) {
      decorators.push(ApiQuery({ name, required: schema.required?.includes(name) ?? false, schema: property }));
    }
  }
  if (access === 'admin' || access === 'client' || access === 'user') {
    decorators.push(ApiBearerAuth(), ApiCookieAuth('bankos_access'));
  } else if (options.bearer) decorators.push(ApiBearerAuth());
  if (options.id) decorators.push(ApiParam({ name: 'id', schema: { type: 'string', format: 'uuid' } }));
  if (options.refreshCookie) decorators.push(ApiCookieAuth('bankos_refresh'));
  if (access === 'platform') decorators.push(ApiBearerAuth(), ApiHeader({ name: 'X-Platform-Key', required: false }));
  if (options.limit === 'money') decorators.push(ApiHeader({
    name: 'Idempotency-Key', required: true, schema: { type: 'string', format: 'uuid' },
    description: 'UUID nuevo para cada operación. Reusa la misma clave para reintentos de esa operación.',
  }));
  return applyDecorators(...decorators);
}

export function traceMiddleware(req: BankRequest, res: Response, next: NextFunction) {
  const requested = req.get('X-Correlation-ID');
  const correlationId = requested && /^[A-Za-z0-9_.:-]{1,128}$/.test(requested) ? requested : randomUUID();
  req.trace = { correlationId, ip: req.ip ?? req.socket.remoteAddress ?? 'unknown' };
  res.setHeader('X-Correlation-ID', correlationId);
  res.setHeader('Cache-Control', 'no-store');
  res.on('finish', () => console.log(JSON.stringify({
    message: 'http.request', correlationId, method: req.method, path: req.path, status: res.statusCode,
  })));
  next();
}

export function readCookie(req: BankRequest, name: string) {
  for (const cookie of (req.get('Cookie') ?? '').split(';')) {
    const [key, ...value] = cookie.trim().split('=');
    if (key === name) return value.join('=');
  }
}

export function readBearer(req: BankRequest) {
  return req.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
}

function validate<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success) throw new BankError(400, 'VALIDATION_ERROR', 'Datos inválidos',
    { fields: parsed.error.issues.map(issue => ({ path: issue.path.join('.'), message: issue.message })) });
  return parsed.data;
}

export function resourceId(id: string) {
  return validate(uuid, id);
}

export class RequestGuard implements CanActivate {
  private readonly ipLimit = integerSetting('RATE_LIMIT_IP', 240);
  private readonly authLimit = integerSetting('RATE_LIMIT_AUTH', 25);
  private readonly loginAccountLimit = integerSetting('RATE_LIMIT_LOGIN_ACCOUNT', 10);
  private readonly moneyLimit = integerSetting('RATE_LIMIT_MONEY', 40);
  private readonly tenantLimit = integerSetting('RATE_LIMIT_TENANT', 400);
  private readonly userLimit = integerSetting('RATE_LIMIT_USER', 160);
  private readonly reflector = new Reflector();

  constructor(private readonly auth: AuthService, private readonly redis: Redis, private readonly origins: string[]) {}

  async canActivate(context: ExecutionContext) {
    const req = context.switchToHttp().getRequest<BankRequest>();
    const contract = this.reflector.get<ContractOptions>(CONTRACT, context.getHandler());
    const access = contract?.access ?? 'user';
    const origin = req.get('Origin');
    if (origin && !['GET', 'HEAD', 'OPTIONS'].includes(req.method) && !this.origins.includes(origin)) forbidden();
    const res = context.switchToHttp().getResponse<Response>();
    if (req.path !== '/api/v1/health') await this.limit(res, `ip:${req.trace.ip}`, this.ipLimit);
    if (contract?.limit === 'auth' || contract?.limit === 'login') await this.limit(res, `auth:${req.trace.ip}`, this.authLimit);

    if (access === 'admin' || access === 'client' || access === 'user') {
      const token = readBearer(req) ?? readCookie(req, ACCESS_COOKIE);
      req.identity = await this.auth.authenticate(token);
      if (access === 'admin' && req.identity.role !== 'ADMIN') forbidden();
      if (access === 'client' && req.identity.role !== 'CLIENT') forbidden();
      const { tenant_id, user_id } = req.identity;
      await this.limit(res, `tenant:${tenant_id}`, this.tenantLimit);
      await this.limit(res, `user:${tenant_id}:${user_id}`, this.userLimit);
      if (contract?.limit === 'money') await this.limit(res, `money:${tenant_id}:${user_id}`, this.moneyLimit);
    }
    if (contract?.limit === 'money') validate(uuid, req.get('Idempotency-Key'));
    if (contract?.limit === 'login') {
      const login = validate(loginInput, req.body);
      const account = createHash('sha256').update(JSON.stringify([login.tenant_slug, login.email])).digest('hex');
      await this.limit(res, `login-account:${account}`, this.loginAccountLimit);
      req.body = login;
    } else if (contract?.body) {
      req.body = validate(contract.body, req.body);
    }
    if (contract?.query) req.validatedQuery = validate(contract.query, req.query);
    return true;
  }

  private async limit(res: Response, bucket: string, threshold: number) {
    let retryAfter: unknown;
    try {
      retryAfter = await this.redis.eval(`
        local total = redis.call('INCR', KEYS[1])
        local remaining = redis.call('PTTL', KEYS[1])
        if remaining < 0 then
          redis.call('PEXPIRE', KEYS[1], 60000)
          remaining = 60000
        end
        if total > tonumber(ARGV[1]) then return math.max(1, math.ceil(remaining / 1000)) end
        return 0
      `, 1, `bankos:rate:${bucket}`, threshold);
    } catch {
      throw new BankError(503, 'RATE_LIMIT_UNAVAILABLE', 'Servicio temporalmente no disponible');
    }
    if (typeof retryAfter === 'number' && retryAfter > 0) {
      res.setHeader('Retry-After', retryAfter);
      throw new BankError(429, 'RATE_LIMIT_EXCEEDED', 'Demasiadas solicitudes');
    }
  }
}

export class ResponseInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler) {
    const req = context.switchToHttp().getRequest<BankRequest>();
    const res = context.switchToHttp().getResponse<Response>();
    return next.handle().pipe(map(data => res.headersSent ? undefined : success(data ?? null, req.trace)));
  }
}

function databaseCode(cause: unknown): string | undefined {
  if (!cause || typeof cause !== 'object') return;
  if ('code' in cause && typeof cause.code === 'string') return cause.code;
  if ('cause' in cause && cause.cause !== cause) return databaseCode(cause.cause);
}

@Catch()
export class ExceptionHandler implements ExceptionFilter {
  catch(cause: unknown, host: ArgumentsHost) {
    const req = host.switchToHttp().getRequest<BankRequest>();
    const res = host.switchToHttp().getResponse<Response>();
    if (res.headersSent) return;
    let error: BankError;
    if (cause instanceof BankError) error = cause;
    else if (cause instanceof HttpException) {
      const status = cause.getStatus();
      error = new BankError(status, status === 404 ? 'NOT_FOUND' : 'HTTP_ERROR',
        status === 404 ? 'Recurso no encontrado' : status < 500 ? 'Solicitud inválida' : 'Error interno');
    } else if (databaseCode(cause) === '23505') error = new BankError(409, 'DUPLICATE_RESOURCE', 'Ya existe un recurso con esos datos');
    else error = new BankError(500, 'INTERNAL_ERROR', 'Error interno');
    const trace = req.trace ?? { correlationId: randomUUID(), ip: 'unknown' };
    if (error.status >= 500) console.error(JSON.stringify({
      message: 'http.error', correlationId: trace.correlationId,
      code: databaseCode(cause) ?? error.code, path: req.path,
    }));
    res.setHeader('X-Correlation-ID', trace.correlationId);
    res.status(error.status).json(failure(error, trace));
  }
}
