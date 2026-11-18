import { Controller, Get, HttpCode, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { TenantsService } from './tenants.service.js';
import { Contract, readBearer, resourceId } from '../common/http.js';
import { platformSessionResponse, tenantConfigResponse, tenantCreatedResponse, tenantDirectoryResponse, tenantStatusResponse } from '../common/response-schemas.js';
import { pageSchema, platformLoginInput, settingsPatch, tenantInput, userStatus } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('tenants')
@Controller('tenants')
export class TenantsController {
  constructor(private readonly tenants: TenantsService) {}

  @Get('directory')
  @Contract({ response: tenantDirectoryResponse, access: 'public', query: pageSchema })
  directory(@Req() req: BankRequest) {
    return this.tenants.directory(req.validatedQuery as Parameters<TenantsService['directory']>[0]);
  }

  @Post('platform-login')
  @HttpCode(200)
  @Contract({ response: platformSessionResponse, access: 'public', body: platformLoginInput, limit: 'auth' })
  platformLogin(@Req() req: BankRequest) {
    return this.tenants.platformLogin(req.body);
  }

  @Post()
  @Contract({ response: tenantCreatedResponse, access: 'platform', body: tenantInput, status: 201 })
  create(@Req() req: BankRequest) {
    return this.tenants.create({ key: req.get('X-Platform-Key'), bearer: readBearer(req) }, req.trace, req.body);
  }

  @Get('config')
  @Contract({ response: tenantConfigResponse, access: 'admin' })
  get(@Req() req: BankRequest) {
    return this.tenants.get(req.identity!);
  }

  @Patch('config')
  @Contract({ response: tenantConfigResponse, access: 'admin', body: settingsPatch })
  update(@Req() req: BankRequest) {
    return this.tenants.update(req.identity!, req.trace, req.body);
  }

  @Patch(':id/status')
  @Contract({ response: tenantStatusResponse, id: true, access: 'platform', body: userStatus })
  status(@Req() req: BankRequest, @Param('id') id: string) {
    return this.tenants.setStatus({ key: req.get('X-Platform-Key'), bearer: readBearer(req) }, req.trace, resourceId(id), req.body.active);
  }
}
