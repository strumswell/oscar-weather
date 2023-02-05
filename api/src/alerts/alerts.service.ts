import { Injectable } from '@nestjs/common';
import { LocationDto } from './dto/location.dto';
import fetch from 'node-fetch';

type Alert = {
  warnId: string;
  type: number;
  level: number;
  start: number;
  end: number;
  bn: boolean;
  instruction: string;
  description: string;
  descriptionText: string;
  event: string;
  headline: string;
};

@Injectable()
export class AlertsService {
  async getAlerts(location: LocationDto): Promise<Alert[]> {
    const alertResponse = await fetch(
      `https://maps.dwd.de/geoserver/dwd/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=dwd:Warnungen_Gemeinden&outputFormat=application%2Fjson&CQL_FILTER=CONTAINS(THE_GEOM,%20POINT(${location.lon}%20${location.lat}))`,
    );
    const alerts: any = await alertResponse.json();
    const warnings = [];
    for (const id in alerts.features) {
      warnings.push({
        warnId: alerts.features[id].properties.IDENTIFIER,
        type: 0,
        level: 0,
        start: new Date(alerts.features[id].properties.ONSET).getTime(),
        end: new Date(alerts.features[id].properties.EXPIRES).getTime(),
        bn: false,
        instruction: alerts.features[id].properties.INSTRUCTION
          ? alerts.features[id].properties.INSTRUCTION
          : '',
        description: alerts.features[id].properties.DESCRIPTION,
        descriptionText: alerts.features[id].properties.DESCRIPTION,
        event: alerts.features[id].properties.EVENT,
        headline: alerts.features[id].properties.HEADLINE,
      });
    }
    return warnings;
  }
}
