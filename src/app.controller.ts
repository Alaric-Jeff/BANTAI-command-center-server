import {
  Controller,
  Get,
  Inject,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Pool, QueryResult } from 'pg';
import { PG_CONNECTION } from './database/database.module';

interface HealthCheckDbRow {
  postgres_version: string;
  postgis_version: string;
  db_time: Date;
}

@Controller('health')
export class AppController {
  constructor(@Inject(PG_CONNECTION) private readonly pool: Pool) {}

  @Get()
  async checkHealth() {
    const startTime = Date.now();

    try {
      const result: QueryResult<HealthCheckDbRow> = await this.pool.query(`
        SELECT 
          version() AS postgres_version, 
          postgis_full_version() AS postgis_version,
          NOW() AS db_time
      `);

      const latencyMs = Date.now() - startTime;
      const row = result.rows[0];

      return {
        status: 'ok',
        timestamp: new Date().toISOString(),
        uptimeSeconds: Math.floor(process.uptime()),
        services: {
          database: {
            status: 'up',
            latencyMs: `${latencyMs}ms`,
            dbTime: row.db_time.toISOString(),
            postgresVersion: row.postgres_version,
            postgisVersion: row.postgis_version,
          },
        },
      };
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error ? error.message : 'Database ping failed';

      throw new ServiceUnavailableException({
        status: 'error',
        timestamp: new Date().toISOString(),
        uptimeSeconds: Math.floor(process.uptime()),
        services: {
          database: {
            status: 'down',
            error: errorMessage,
          },
        },
      });
    }
  }
}
