import { IsEmail, IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class EmailPasswordDto {
  @IsString()
  @IsEmail()
  @IsNotEmpty()
  email!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128, { message: 'Exceeded expected character length' })
  password!: string;
}
