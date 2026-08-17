import {
  Injectable,
  UnauthorizedException,
  Logger,
  InternalServerErrorException,
} from '@nestjs/common';
import { JwtService, JwtSignOptions } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';
import ms from 'ms';
import { AuthRepository } from './auth.repository';
import { LocalSignInDTO } from './dto/local-signin.dto';
import { JwtPayload } from './interfaces/jwt-payload.interface';
import { Role } from './enums/role.enum';

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly authRepository: AuthRepository,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  private createPayload(userId: string, role: Role): JwtPayload {
    return {
      sub: userId,
      role: role,
    };
  }

  private hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  async localLogin(dto: LocalSignInDTO): Promise<AuthTokens> {
    const { badge_number, password } = dto;

    try {
      const user =
        await this.authRepository.findUserByBadgeNumber(badge_number);

      if (!user) {
        this.logger.warn(`Failed login attempt for badge: ${badge_number}`);
        throw new UnauthorizedException('Invalid badge number or password.');
      }

      if (user.deleted_at !== null) {
        this.logger.warn(
          `Deactivated badge tried to authenticate: ${badge_number}`,
        );
        throw new UnauthorizedException('Invalid badge number or password.');
      }

      const isPasswordValid = await bcrypt.compare(
        password,
        user.password_hash,
      );
      if (!isPasswordValid) {
        this.logger.warn(`Invalid password for badge: ${badge_number}`);
        throw new UnauthorizedException('Invalid badge number or password.');
      }

      const payload = this.createPayload(user.id, user.role);

      const [accessToken, refreshToken] = await Promise.all([
        this.jwtService.signAsync(payload, {
          secret: this.configService.getOrThrow<string>('JWT_SECRET'),
          expiresIn: this.configService.getOrThrow<string>(
            'JWT_EXPIRATION',
          ) as JwtSignOptions['expiresIn'],
        }),
        this.jwtService.signAsync(
          { sub: user.id },
          {
            secret: this.configService.getOrThrow<string>('JWT_REFRESH_SECRET'),
            expiresIn: this.configService.getOrThrow<string>(
              'JWT_REFRESH_EXPIRATION',
            ) as JwtSignOptions['expiresIn'],
          },
        ),
      ]);

      // 6. Persist hashed refresh token session in PostgreSQL
      const refreshTokenHash = this.hashToken(refreshToken);
      const refreshTtl = this.configService.getOrThrow<string>(
        'JWT_REFRESH_EXPIRATION',
      );
      // Dynamically compute expiresAt matching config string (e.g., '7d', '12h', '1d')
      const expiresAt = new Date(Date.now() + ms(refreshTtl as ms.StringValue));

      await this.authRepository.createSession(
        user.id,
        refreshTokenHash,
        expiresAt,
      );

      return {
        accessToken,
        refreshToken,
      };
    } catch (err) {
      if (err instanceof UnauthorizedException) {
        throw err;
      }
      this.logger.error(
        `Error during local login for badge ${badge_number}`,
        err,
      );
      throw new InternalServerErrorException('Authentication failed.');
    }
  }
}
