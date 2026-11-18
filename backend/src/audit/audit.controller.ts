import { Controller, Get, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { z } from 'zod';
import { AuditService } from './audit.service.js';
import { Contract } from '../common/http.js';
import { auditListResponse } from '../common/response-schemas.js';
import { pageSchema } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('audit')
@Controller('audit')
export class AuditController {
  constructor(private readonly audit: AuditService) {}

  @Get()
  @Contract({ response: auditListResponse, access: 'admin', query: pageSchema })
  list(@Req() req: BankRequest) {
    return this.audit.list(req.identity!, req.validatedQuery as z.infer<typeof pageSchema>);
  }
}
