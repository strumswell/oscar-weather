import { CacheModule, Module } from '@nestjs/common';
import { AlertsModule } from './alerts/alerts.module';
import { RainModule } from './rain/rain.module';
import { MapshotsModule } from './mapshots/mapshots.module';
import { ServeStaticModule } from '@nestjs/serve-static';
import { join } from 'path';

@Module({
  imports: [
    AlertsModule,
    RainModule,
    MapshotsModule,
    CacheModule.register({ isGlobal: true }),
    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', 'www'),
    }),
  ],
})
export class AppModule {}
