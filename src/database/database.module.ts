import { Global, Module } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { SeederService } from './seeder.service';

@Global()
@Module({
  providers: [DatabaseService, SeederService],
  exports: [DatabaseService],
})
export class DatabaseModule {}
