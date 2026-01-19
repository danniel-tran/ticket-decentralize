import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { SuiModule } from './sui/sui.module';
import configuration from './config/configuration';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
    }),
    SuiModule,
  ],
  exports: [SuiModule],
})
export class CommonModule {}
