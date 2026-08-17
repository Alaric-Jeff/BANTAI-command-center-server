import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class LocalSignInDTO {
  @IsString()
  @IsNotEmpty()
  badge_number!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128, { message: 'Exceeded expected character length' })
  password!: string;
}
