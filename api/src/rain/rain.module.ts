import { Module } from '@nestjs/common';
import { RainService } from './rain.service';
import { RainController } from './rain.controller';

@Module({
  imports: [],
  controllers: [RainController],
  providers: [RainService],
})
export class RainModule {}
