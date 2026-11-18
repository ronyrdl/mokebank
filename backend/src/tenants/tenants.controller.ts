import { Controller, Get, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { TenantsService } from './tenants.service.js';
import { Contract, resourceId } from '../common/http.js';
import { tenantConfigResponse, tenantCreatedResponse, tenantStatusResponse } from '../common/response-schemas.js';
import { settingsPatch, tenantInput, userStatus } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('tenants')
@Controller('tenants')
export class TenantsController {
  constructor(private readonly tenants: TenantsService) {}

  @Post()
  @Contract({ response: tenantCreatedResponse, access: 'platform', body: tenantInput, status: 201 })
  create(@Req() req: BankRequest) {
    return this.tenants.create(req.get('X-Platform-Key'), req.trace, req.body);
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
    return this.tenants.setStatus(req.get('X-Platform-Key'), req.trace, resourceId(id), req.body.active);
  }
}
