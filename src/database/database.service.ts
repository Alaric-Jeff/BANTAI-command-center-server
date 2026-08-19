import {
  Injectable,
  Logger,
  OnModuleInit,
  OnApplicationShutdown,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';

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

  async query<T extends QueryResultRow = any>(
    text: string,
    params?: any[],
  ): Promise<QueryResult<T>> {
    return this.pool.query<T>(text, params);
  }

  getPool(): Pool {
    return this.pool;
  }

  /**
   * Runs a set of queries against a single, dedicated client wrapped in
   * BEGIN/COMMIT/ROLLBACK, so multiple statements either all succeed or
   * all roll back together. Use this whenever a piece of logic needs
   * more than one write to land atomically (e.g. rotating a refresh
   * session: delete old + insert new as one unit).
   *
   * IMPORTANT: inside the callback, always query via the provided
   * `client` parameter — never via `this.query()` or `this.pool` — or
   * those calls will run on a different connection outside the
   * transaction and won't be included in the commit/rollback.
   *
   * On any thrown error inside `fn`, the transaction is rolled back and
   * the original error is re-thrown to the caller (not swallowed), so
   * callers can still catch and handle/log it normally. The client is
   * always released back to the pool in a `finally`, whether the
   * transaction commits, rolls back, or the callback throws before
   * either.
   */
  async withTransaction<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();

    try {
      await client.query('BEGIN');
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (error: unknown) {
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError: unknown) {
        const rollbackMessage =
          rollbackError instanceof Error
            ? rollbackError.message
            : 'Unknown error during rollback';
        this.logger.error(
          `Failed to roll back transaction cleanly: ${rollbackMessage}`,
        );
      }
      throw error;
    } finally {
      client.release();
    }
  }
}
