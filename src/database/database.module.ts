import {
  Global,
  Module,
  OnApplicationShutdown,
  Inject,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, QueryResult } from 'pg';

export const PG_CONNECTION = 'PG_CONNECTION';

interface TimeRow {
  now: Date;
}

@Global()
@Module({
  providers: [
    {
      provide: PG_CONNECTION,
      inject: [ConfigService],
      useFactory: async (configService: ConfigService) => {
        const logger = new Logger('DatabaseConnectionFactory');

        const pool = new Pool({
          connectionString: configService.get<string>('DATABASE_URL'),
          max: configService.get<number>('DB_POOL_MAX', 20),
          idleTimeoutMillis: configService.get<number>(
            'DB_POOL_IDLE_TIMEOUT',
            30000,
          ),
          connectionTimeoutMillis: configService.get<number>(
            'DB_POOL_CONN_TIMEOUT',
            2000,
          ),
        });

        try {
          const res: QueryResult<TimeRow> = await pool.query('SELECT NOW()');
          logger.log(
            `PostgreSQL connected successfully at: ${res.rows[0].now.toISOString()}`,
          );
        } catch (error: unknown) {
          const errorMessage =
            error instanceof Error ? error.message : 'Unknown database error';
          logger.error(`Failed to connect to the database: ${errorMessage}`);
          process.exit(1);
        }

        pool.on('error', (error: Error) => {
          logger.error(
            `Unexpected error on idle database client: ${error.message}`,
            error.stack,
          );
          process.exit(1);
        });

        return pool;
      },
    },
  ],
  exports: [PG_CONNECTION],
})
export class DatabaseModule implements OnApplicationShutdown {
  private readonly logger = new Logger(DatabaseModule.name);

  constructor(@Inject(PG_CONNECTION) private readonly pool: Pool) {}

  async onApplicationShutdown(signal?: string) {
    this.logger.log(
      `Received ${signal || 'shutdown signal'}. Draining PostgreSQL connection pool...`,
    );
    try {
      await this.pool.end();
      this.logger.log('Database pool closed safely.');
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error
          ? error.message
          : 'Unknown error during shutdown';
      this.logger.error(`Error while closing database pool: ${errorMessage}`);
    }
  }
}
