import { Controller, Get, Param, Patch, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { UsersService } from './users.service.js';
import { Contract, resourceId } from '../common/http.js';
import { userListResponse, userResponse } from '../common/response-schemas.js';
import { pageSchema, updateUser, userInput, userStatus } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';
import type { z } from 'zod';

@ApiTags('users')
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Post()
  @Contract({ response: userResponse, access: 'admin', body: userInput, status: 201 })
  create(@Req() req: BankRequest) {
    return this.users.create(req.identity!, req.trace, req.body);
  }

  @Get()
  @Contract({ response: userListResponse, access: 'admin', query: pageSchema })
  list(@Req() req: BankRequest) {
    return this.users.list(req.identity!, req.validatedQuery as z.infer<typeof pageSchema>);
  }

  @Get(':id')
  @Contract({ response: userResponse, id: true, access: 'admin' })
  get(@Req() req: BankRequest, @Param('id') id: string) {
    return this.users.get(req.identity!, resourceId(id));
  }

  @Patch(':id')
  @Contract({ response: userResponse, id: true, access: 'admin', body: updateUser })
  update(@Req() req: BankRequest, @Param('id') id: string) {
    return this.users.update(req.identity!, req.trace, resourceId(id), req.body);
  }

  @Patch(':id/status')
  @Contract({ response: userResponse, id: true, access: 'admin', body: userStatus })
  status(@Req() req: BankRequest, @Param('id') id: string) {
    return this.users.status(req.identity!, req.trace, resourceId(id), req.body.active);
  }
}
