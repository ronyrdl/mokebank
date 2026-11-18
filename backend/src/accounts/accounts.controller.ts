import { Controller, Get, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { z } from 'zod';
import { AccountsService } from './accounts.service.js';
import { TransactionsService } from '../transactions/transactions.service.js';
import { Contract, resourceId } from '../common/http.js';
import { accountListResponse, accountResponse, transactionListResponse } from '../common/response-schemas.js';
import { accountInput, accountStatus, historySchema, pageSchema, updateAccount } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('accounts')
@Controller('accounts')
export class AccountsController {
  constructor(private readonly accounts: AccountsService, private readonly transactions: TransactionsService) {}

  @Post()
  @Contract({ response: accountResponse, access: 'admin', body: accountInput, status: 201 })
  create(@Req() req: BankRequest) {
    return this.accounts.create(req.identity!, req.trace, req.body);
  }

  @Get()
  @Contract({ response: accountListResponse, query: pageSchema })
  list(@Req() req: BankRequest) {
    return this.accounts.list(req.identity!, req.validatedQuery as z.infer<typeof pageSchema>);
  }

  @Get(':id')
  @Contract({ response: accountResponse, id: true })
  get(@Req() req: BankRequest, @Param('id') id: string) {
    return this.accounts.get(req.identity!, resourceId(id));
  }

  @Patch(':id')
  @Contract({ response: accountResponse, id: true, access: 'admin', body: updateAccount })
  update(@Req() req: BankRequest, @Param('id') id: string) {
    return this.accounts.update(req.identity!, req.trace, resourceId(id), req.body.number);
  }

  @Patch(':id/status')
  @Contract({ response: accountResponse, id: true, access: 'admin', body: accountStatus })
  status(@Req() req: BankRequest, @Param('id') id: string) {
    return this.accounts.status(req.identity!, req.trace, resourceId(id), req.body.status);
  }

  @Get(':id/transactions')
  @Contract({ response: transactionListResponse, id: true, query: historySchema })
  history(@Req() req: BankRequest, @Param('id') id: string) {
    return this.transactions.history(req.identity!, req.validatedQuery as z.infer<typeof historySchema>, undefined, resourceId(id));
  }
}
