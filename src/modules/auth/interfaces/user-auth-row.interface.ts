import { Role } from '../enums/role.enum';

export interface UserAuthRow {
  id: string;
  password_hash: string;
  deleted_at: Date | null;
  role: Role;
  command_center_id: string | null;
}
