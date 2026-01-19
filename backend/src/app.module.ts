import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { CommonModule } from './common/common.module';
import { EventsModule } from './events/events.module';
import { TicketsModule } from './tickets/tickets.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [CommonModule, EventsModule, TicketsModule, UsersModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}