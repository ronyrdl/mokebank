import { Controller, Get, Put, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrenciesService } from './currencies.service.js';
import { Contract } from '../common/http.js';
import { currencyListResponse, ratesResponse } from '../common/response-schemas.js';
import { ratesInput } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('currencies')
@Controller('currencies')
export class CurrenciesController {
  constructor(private readonly currencies: CurrenciesService) {}

  @Get()
  @Contract({ response: currencyListResponse })
  list() {
    return this.currencies.list();
  }

  @Get('rates')
  @Contract({ response: ratesResponse })
  rates(@Req() req: BankRequest) {
    return this.currencies.rates(req.identity!);
  }

  @Put('rates')
  @Contract({ response: ratesResponse, access: 'admin', body: ratesInput })
  update(@Req() req: BankRequest) {
    return this.currencies.update(req.identity!, req.trace, req.body.rates);
  }
}
