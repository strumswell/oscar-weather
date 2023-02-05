import { Injectable } from '@nestjs/common';
import { LocationDto } from '../alerts/dto/location.dto';
import fetch from 'node-fetch';
import { parseStringPromise } from 'xml2js';
import * as pLimit from 'p-limit';

@Injectable()
export class RainService {
  async getRainForecast(location: LocationDto): Promise<any> {
    // get capabilities for dwd:Niederschlagsradar
    const capabilitiesResponse = await fetch(
      'https://maps.dwd.de/geoserver/dwd/Niederschlagsradar/wms?REQUEST=GetCapabilities&SERVICE=WMS&VERSION=1.3.0',
    );
    const capabilities: any = await capabilitiesResponse.text();
    const parsedCapabilites = await parseStringPromise(capabilities);

    const [startTimestamp, endTimestamp] =
      parsedCapabilites.WMS_Capabilities.Capability[0].Layer[0].Layer[0].Layer[0].Layer[0].Layer[0].Dimension[0][
        '_'
      ].split('/');

    // fetch current gray index
    const lon1 = location.lon - 0.001;
    const lat1 = location.lat - 0.001;
    const lon2 = location.lon + 0.001;
    const lat2 = location.lat + 0.001;
    const url = `https://maps.dwd.de/geoserver/dwd/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo&QUERY_LAYERS=dwd:Niederschlagsradar&STYLES&LAYERS=dwd:Niederschlagsradar&INFO_FORMAT=application/json&FEATURE_COUNT=50&X=50&Y=50&SRS=EPSG:4326&WIDTH=101&HEIGHT=101&BBOX=${lon1},${lat1},${lon2},${lat2}`;
    const grayIndexResponse = await fetch(url);
    const currentGrayIndex: any = await grayIndexResponse.json();

    if (currentGrayIndex.features.length === 0) {
      return { data: [] };
    }

    // generate dwd URLs for each timestamp between current time and endTimestamp in 5 minute steps
    const urls = [];
    const time = new Date(currentGrayIndex.features[0].properties.TIME);
    while (
      time.getTime() <= new Date(endTimestamp).getTime() &&
      urls.length < 13
    ) {
      urls.push(
        `https://maps.dwd.de/geoserver/dwd/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetFeatureInfo&QUERY_LAYERS=dwd:Niederschlagsradar&STYLES&LAYERS=dwd:Niederschlagsradar&INFO_FORMAT=application/json&FEATURE_COUNT=50&X=50&Y=50&SRS=EPSG:4326&WIDTH=101&HEIGHT=101&BBOX=${lon1},${lat1},${lon2},${lat2}&TIME=${time.toISOString()}`,
      );
      time.setMinutes(time.getMinutes() + 5);
    }

    // fetch all urls and get the GRAY_INDEX from each json response
    const limit = pLimit(5);
    const grayIndexValues = await Promise.allSettled(
      urls.map(async (url) => {
        const grayIndexResponse = await limit(() => fetch(url));
        const grayIndex: any = await grayIndexResponse.json();
        return {
          time: grayIndex.features[0].properties.TIME,
          mmh: grayIndex.features[0].properties.GRAY_INDEX * 10,
        };
      }),
    );

    const filteredValue = grayIndexValues
      .filter((value) => value.status === 'fulfilled')
      .map((value: any) => value.value);

    return { data: filteredValue };
  }
}
