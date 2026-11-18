import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module.js';
import { AuthService } from './auth/auth.service.js';
import { ACCESS_COOKIE, REFRESH_COOKIE, ExceptionHandler, RequestGuard, ResponseInterceptor, traceMiddleware } from './common/http.js';
import { integerSetting } from './common/config.js';
import { REDIS } from './common/redis.js';

export async function createApp() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { abortOnError: false });
  const origins = (process.env.CORS_ORIGINS ?? '').split(',').map(origin => origin.trim()).filter(Boolean);
  app.setGlobalPrefix('api/v1');
  app.getHttpAdapter().getInstance().disable('x-powered-by');
  app.set('trust proxy', integerSetting('TRUST_PROXY_HOPS', 0, 0));
  app.use(traceMiddleware);
  if (origins.length) app.enableCors({
    origin: origins, credentials: true, exposedHeaders: ['X-Correlation-ID', 'Retry-After'],
  });
  app.useGlobalGuards(new RequestGuard(app.get(AuthService), app.get(REDIS), origins));
  app.useGlobalInterceptors(new ResponseInterceptor());
  app.useGlobalFilters(new ExceptionHandler());
  const options = new DocumentBuilder().setTitle('BankOS API').setVersion('1.0')
    .setDescription('API bancaria multitenant. Importes monetarios y tasas como cadenas decimales. Los clientes acceden a sus propias cuentas.')
    .addBearerAuth().addCookieAuth(ACCESS_COOKIE, { type: 'apiKey', in: 'cookie' }, 'bankos_access')
    .addCookieAuth(REFRESH_COOKIE, { type: 'apiKey', in: 'cookie' }, 'bankos_refresh').build();
  SwaggerModule.setup('api/docs', app, () => SwaggerModule.createDocument(app, options));
  return app;
}
