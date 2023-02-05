import {
  CacheInterceptor,
  CacheTTL,
  Controller,
  Get,
  Query,
  UseInterceptors,
} from '@nestjs/common';
import { AlertsService } from './alerts.service';
import { LocationDto } from './dto/location.dto';

@Controller('alerts')
@UseInterceptors(CacheInterceptor)
export class AlertsController {
  constructor(private readonly alertsService: AlertsService) {}

  @Get()
  @CacheTTL(60)
  getAlerts(@Query() location: LocationDto) {
    return this.alertsService.getAlerts(location);
  }
}
