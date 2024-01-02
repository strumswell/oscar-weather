import { Type } from "class-transformer";
import { IsNumber, IsOptional, IsString } from "class-validator";
export class LocationDto {
  @IsNumber()
  @Type(() => Number)
  lat: number;

  @IsNumber()
  @Type(() => Number)
  lon: number;

  @IsNumber()
  @Type(() => Number)
  @IsOptional()
  map?: number;
}
