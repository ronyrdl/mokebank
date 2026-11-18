import { Controller, Get, Patch, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { WebhooksService } from './webhooks.service.js';
import { Contract } from '../common/http.js';
import { nullableWebhookResponse, webhookResponse } from '../common/response-schemas.js';
import { webhookInput, webhookPatch } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('webhooks')
@Controller('webhooks/config')
export class WebhooksController {
  constructor(private readonly webhooks: WebhooksService) {}

  @Get()
  @Contract({ response: nullableWebhookResponse, access: 'admin' })
  get(@Req() req: BankRequest) {
    return this.webhooks.get(req.identity!);
  }

  @Post()
  @Contract({ response: webhookResponse, access: 'admin', body: webhookInput, status: 201 })
  create(@Req() req: BankRequest) {
    return this.webhooks.change(req.identity!, req.trace, req.body, true);
  }

  @Patch()
  @Contract({ response: webhookResponse, access: 'admin', body: webhookPatch })
  update(@Req() req: BankRequest) {
    return this.webhooks.change(req.identity!, req.trace, req.body, false);
  }
}
