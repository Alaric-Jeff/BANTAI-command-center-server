import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';
import { LocalUserRow } from './interfaces/user-local.interface';

@Injectable()
export class AuthRepository {
  constructor(private readonly db: DatabaseService) {}

  async findUserByBadgeNumber(
    badgeNumber: string,
  ): Promise<LocalUserRow | null> {
    const sql = `
      SELECT id, password_hash, role, deleted_at 
      FROM user_accounts 
      WHERE badge_number = $1
      LIMIT 1;
    `;

    const { rows } = await this.db.query<LocalUserRow>(sql, [badgeNumber]);
    return rows[0] || null;
  }

  async createSession(
    userId: string,
    refreshTokenHash: string,
    expiresAt: Date,
  ): Promise<void> {
    const sql = `
      INSERT INTO user_sessions (user_id, refresh_token_hash, expires_at)
      VALUES ($1, $2, $3);
    `;

    await this.db.query(sql, [userId, refreshTokenHash, expiresAt]);
  }
}
