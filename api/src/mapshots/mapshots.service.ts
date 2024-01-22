import { CACHE_MANAGER, Inject, Injectable } from "@nestjs/common";
import { InjectContext } from "nest-puppeteer";
import type { BrowserContext } from "puppeteer";
import { LocationDto } from "../alerts/dto/location.dto";
import { Cache } from "cache-manager";

@Injectable()
export class MapshotsService {
  constructor(
    @InjectContext() private readonly browserContext: BrowserContext,
    @Inject(CACHE_MANAGER) private cacheManager: Cache
  ) {}
  async getMapshot(location: LocationDto): Promise<Buffer> {
    const cached = await this.cacheManager.get(`mapshot-${location.lat.toFixed(2)}-${location.lon.toFixed(2)}`);
    if (cached) {
      return cached;
    }
    const page = await this.browserContext.newPage();
    await page.setViewport({ width: 512, height: 512 });
    await page.goto(
      `http://localhost:8080/index.html?lat=${location.lat}&lon=${location.lon}&map=${location.map ?? 6}`,
      { timeout: 30000, waitUntil: "networkidle0" }
    );
    await new Promise((resolve) => setTimeout(resolve, 500));
    const mapshot = await page.screenshot({ type: "jpeg", quality: 80 });
    page.close();

    await this.cacheManager.set(`mapshot-${location.lat.toFixed(2)}-${location.lon.toFixed(2)}`, mapshot, 60);
    return mapshot;
  }
}
