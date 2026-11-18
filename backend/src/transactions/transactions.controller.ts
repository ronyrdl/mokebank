import { Controller, Get, Param, Post, Req, Res } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import type { z } from 'zod';
import { TransactionsService } from './transactions.service.js';
import { Contract, resourceId } from '../common/http.js';
import { transactionListResponse, transactionResponse, transactionStatsResponse } from '../common/response-schemas.js';
import { depositInput, historySchema, transferInput, transferQuote, transferQuoteInput, type transactionType } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

@ApiTags('transactions')
@Controller('transactions')
export class TransactionsController {
  constructor(private readonly transactions: TransactionsService) {}

  @Post('deposit')
  @Contract({ response: transactionResponse, access: 'client', body: depositInput, limit: 'money', status: 201,
    example: { account_id: '4e718ef8-7280-4443-88f1-3a186de2a17c', amount: '25.00' } })
  deposit(@Req() req: BankRequest, @Res() res: Response) {
    return this.post(req, res, 'DEPOSIT');
  }

  @Post('withdraw')
  @Contract({ response: transactionResponse, access: 'client', body: depositInput, limit: 'money', status: 201,
    example: { account_id: '4e718ef8-7280-4443-88f1-3a186de2a17c', amount: '25.00' } })
  withdraw(@Req() req: BankRequest, @Res() res: Response) {
    return this.post(req, res, 'WITHDRAW');
  }

  @Post('transfer')
  @Contract({ response: transactionResponse, access: 'client', body: transferInput, limit: 'money', status: 201,
    example: { source_account_id: '4e718ef8-7280-4443-88f1-3a186de2a17c', destination_account_number: '900000102', amount: '25.00' } })
  transfer(@Req() req: BankRequest, @Res() res: Response) {
    return this.post(req, res, 'TRANSFER');
  }

  @Get()
  @Contract({ response: transactionListResponse, query: historySchema })
  list(@Req() req: BankRequest) {
    return this.transactions.history(req.identity!, req.validatedQuery as z.infer<typeof historySchema>);
  }

  @Get('stats')
  @Contract({ response: transactionStatsResponse, access: 'admin' })
  stats(@Req() req: BankRequest) {
    return this.transactions.stats(req.identity!);
  }

  @Get('quote')
  @Contract({ access: 'client', query: transferQuoteInput, response: transferQuote })
  quote(@Req() req: BankRequest) {
    return this.transactions.quote(req.identity!, req.validatedQuery as z.infer<typeof transferQuoteInput>);
  }

  @Get(':id')
  @Contract({ response: transactionResponse, id: true })
  get(@Req() req: BankRequest, @Param('id') id: string) {
    return this.transactions.history(req.identity!, {}, resourceId(id));
  }

  private async post(req: BankRequest, res: Response, type: z.infer<typeof transactionType>) {
    const key = req.get('Idempotency-Key')!.toLowerCase();
    const result = await this.transactions.execute(req.identity!, req.trace, key, type, req.body);
    res.status(result.status).type('application/json').send(result.body);
  }
}
