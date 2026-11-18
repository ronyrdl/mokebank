import { Controller, Get, HttpCode, Post, Req, Res } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { CookieOptions, Response } from 'express';
import { AuthService } from './auth.service.js';
import { UsersService } from '../users/users.service.js';
import { ACCESS_COOKIE, Contract, readBearer, readCookie, REFRESH_COOKIE } from '../common/http.js';
import { logoutResponse, selfRegistrationResponse, sessionResponse, userResponse } from '../common/response-schemas.js';
import { loginInput, selfRegistrationInput, userInput } from '../common/schemas.js';
import type { BankRequest } from '../common/types.js';

function cookie(path: string): CookieOptions {
  return { httpOnly: true, secure: process.env.COOKIE_SECURE !== 'false', sameSite: 'strict', path };
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, private readonly users: UsersService) {}

  @Post('register')
  @Contract({ response: userResponse, access: 'admin', body: userInput, limit: 'auth', status: 201 })
  register(@Req() req: BankRequest) {
    return this.users.create(req.identity!, req.trace, req.body);
  }

  @Post('self-register')
  @Contract({ response: selfRegistrationResponse, access: 'public', body: selfRegistrationInput, limit: 'auth', status: 201 })
  selfRegister(@Req() req: BankRequest) {
    return this.users.selfRegister(req.trace, req.body);
  }

  @Post('login')
  @HttpCode(200)
  @Contract({ response: sessionResponse, access: 'public', body: loginInput, limit: 'login',
    example: { tenant_slug: 'demo-a', email: 'cliente01@demo-a.example', password: 'BankOS-demo-2026!' } })
  async login(@Req() req: BankRequest, @Res({ passthrough: true }) res: Response) {
    return this.setSession(res, await this.auth.login(req.body));
  }

  @Post('refresh')
  @HttpCode(200)
  @Contract({ access: 'public', limit: 'auth', refreshCookie: true, response: sessionResponse })
  async refresh(@Req() req: BankRequest, @Res({ passthrough: true }) res: Response) {
    return this.setSession(res, await this.auth.refresh(readCookie(req, REFRESH_COOKIE)));
  }

  @Post('logout')
  @HttpCode(200)
  @Contract({ access: 'public', limit: 'auth', refreshCookie: true, bearer: true, response: logoutResponse })
  async logout(@Req() req: BankRequest, @Res({ passthrough: true }) res: Response) {
    await this.auth.logout(readCookie(req, REFRESH_COOKIE), readBearer(req));
    res.clearCookie(ACCESS_COOKIE, cookie('/api/v1'));
    res.clearCookie(REFRESH_COOKIE, cookie('/api/v1/auth'));
    return { logged_out: true };
  }

  @Get('me')
  @Contract({ response: userResponse })
  me(@Req() req: BankRequest) {
    return this.auth.me(req.identity!);
  }

  private setSession(res: Response, session: Awaited<ReturnType<AuthService['login']>>) {
    res.cookie(ACCESS_COOKIE, session.access, { ...cookie('/api/v1'), maxAge: this.auth.accessSeconds * 1000 });
    res.cookie(REFRESH_COOKIE, session.refresh, { ...cookie('/api/v1/auth'), maxAge: this.auth.refreshSeconds * 1000 });
    return { user: session.user, access_token: session.access, token_type: 'Bearer', expires_in: this.auth.accessSeconds };
  }
}
