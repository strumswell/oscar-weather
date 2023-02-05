import {
  CacheInterceptor,
  CacheTTL,
  Controller,
  Get,
  Header,
  Query,
  Res,
  StreamableFile,
  UseInterceptors,
} from '@nestjs/common';
import { MapshotsService } from './mapshots.service';
import { Response } from 'express';
import { LocationDto } from '../alerts/dto/location.dto';

@Controller('mapshots')
export class MapshotsController {
  constructor(private readonly mapshotsService: MapshotsService) {}

  @Get('radar')
  @Header('Content-Type', 'image/jpeg')
  async getMapshot(
    @Res({ passthrough: true }) res: Response,
    @Query() location: LocationDto,
  ) {
    const image = await this.mapshotsService.getMapshot(location);
    res.set({
      'Content-Type': 'image/jpeg',
    });
    return new StreamableFile(image);
  }
}
