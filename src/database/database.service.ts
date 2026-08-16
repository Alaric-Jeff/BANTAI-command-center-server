import {
  Injectable,
  Logger,
  OnModuleInit,
  OnApplicationShutdown,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, QueryResult, QueryResultRow } from 'pg';

interface TimeRow {
  now: Date;
}

@Injectable()
export class DatabaseService implements OnModuleInit, OnApplicationShutdown {
  private readonly logger = new Logger(DatabaseService.name);
  private readonly pool: Pool;

  constructor(private readonly configService: ConfigService) {
    this.pool = new Pool({
      connectionString: this.configService.get<string>('DATABASE_URL'),
      max: this.configService.get<number>('DB_POOL_MAX', 20),
      idleTimeoutMillis: this.configService.get<number>(
        'DB_POOL_IDLE_TIMEOUT',
        30000,
      ),
      connectionTimeoutMillis: this.configService.get<number>(
        'DB_POOL_CONN_TIMEOUT',
        2000,
      ),
    });

    this.pool.on('error', (error: Error) => {
      this.logger.error(
        `Unexpected error on idle database client: ${error.message}`,
        error.stack,
      );
      process.exit(1);
    });
  }

  async onModuleInit() {
    try {
      const res: QueryResult<TimeRow> = await this.pool.query('SELECT NOW()');
      this.logger.log(
        `PostgreSQL connected successfully at: ${res.rows[0].now.toISOString()}`,
      );
    } catch (error: unknown) {
      const errorMessage =
        error instanceof Error ? error.message : 'Unknown database error';
      this.logger.error(`Failed to connect to the database: ${errorMessage}`);
      process.exit(1);
    }
  }

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

  // Wrapper method so you don't have to expose the raw pool everywhere
  async query<T extends QueryResultRow = any>(
    text: string,
    params?: any[],
  ): Promise<QueryResult<T>> {
    return this.pool.query<T>(text, params);
  }

  // Useful if you need the raw client for transactions
  getPool(): Pool {
    return this.pool;
  }
}
