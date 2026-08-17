import { Role } from '../enums/role.enum';

export interface LocalUserRow {
  id: string;
  password_hash: string;
  deleted_at: Date | null;
  role: Role;
}
