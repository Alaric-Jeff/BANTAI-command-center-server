import type { FastifyRequest } from 'fastify';

export interface RequestWithCookies extends FastifyRequest {
  cookies: Record<string, string | undefined>;
}
