import { Type } from 'class-transformer';
import { IsNumber, IsString } from 'class-validator';
export class LocationDto {
  @IsNumber()
  @Type(() => Number)
  lat: number;

  @IsNumber()
  @Type(() => Number)
  lon: number;
}
