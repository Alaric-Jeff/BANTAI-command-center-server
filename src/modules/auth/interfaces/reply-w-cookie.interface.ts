import type { FastifyReply } from 'fastify';
import type { CookieSerializeOptions } from '@fastify/cookie';

export interface ReplyWithCookie extends FastifyReply {
  setCookie(
    name: string,
    value: string,
    options?: CookieSerializeOptions,
  ): ReplyWithCookie;
}
