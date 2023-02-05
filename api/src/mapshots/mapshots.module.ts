import { Module } from '@nestjs/common';
import { PuppeteerModule } from 'nest-puppeteer';
import { MapshotsController } from './mapshots.controller';
import { MapshotsService } from './mapshots.service';

@Module({
  imports: [PuppeteerModule.forRoot()],
  controllers: [MapshotsController],
  providers: [MapshotsService],
})
export class MapshotsModule {}
