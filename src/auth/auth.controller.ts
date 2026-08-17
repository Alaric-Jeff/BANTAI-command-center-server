import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  Res,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { FastifyReply } from 'fastify';
import type { CookieSerializeOptions } from '@fastify/cookie';
import ms from 'ms';
import { AuthService } from './auth.service';
import { LocalSignInDTO } from './dto/local-signin.dto';

const parseMs = ms as unknown as (value: string) => number;

interface ReplyWithCookie extends FastifyReply {
  setCookie(
    name: string,
    value: string,
    options?: CookieSerializeOptions,
  ): ReplyWithCookie;
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly configService: ConfigService,
  ) {}

  @HttpCode(HttpStatus.OK)
  @Post('local/signin')
  async localSignIn(
    @Body() dto: LocalSignInDTO,
    @Res({ passthrough: true }) response: FastifyReply,
  ): Promise<{ accessToken: string }> {
    const { accessToken, refreshToken } =
      await this.authService.localLogin(dto);
    const refreshTtl = this.configService.getOrThrow<string>(
      'JWT_REFRESH_EXPIRATION',
    );
    const maxAgeInSeconds = parseMs(refreshTtl) / 1000;
    (response as ReplyWithCookie).setCookie('refresh_token', refreshToken, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/auth/refresh',
      maxAge: maxAgeInSeconds,
    });
    return { accessToken };
  }
}
