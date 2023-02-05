import {
  CacheInterceptor,
  CacheTTL,
  Controller,
  Get,
  Query,
  UseInterceptors,
} from '@nestjs/common';
import { LocationDto } from '../alerts/dto/location.dto';
import { RainService } from './rain.service';

@Controller('rain')
@UseInterceptors(CacheInterceptor)
export class RainController {
  constructor(private readonly rainService: RainService) {}

  @Get()
  @CacheTTL(60)
  getRain(@Query() location: LocationDto) {
    return this.rainService.getRainForecast(location);
  }
}
