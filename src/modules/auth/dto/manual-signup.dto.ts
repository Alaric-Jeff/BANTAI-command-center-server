import { IsEmail, IsString, Length, Matches } from 'class-validator';

export class ManualSignupDto {
  @IsEmail()
  email!: string;

  @IsString()
  @Length(8, 128, { message: 'Password must be between 8 and 128 characters.' })
  @Matches(/^(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).*$/, {
    message:
      'Password must contain at least 1 uppercase letter, 1 number, and 1 special character.',
  })
  password!: string;
}
