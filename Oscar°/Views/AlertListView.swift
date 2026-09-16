//
//  AlertListView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 01.12.21.
//
//  The Wetter tab's warning sheet — same card UI as the map's polygon
//  tap sheet (AlertInfoSheet).
//

import SwiftUI

struct AlertListView: View {
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        AlertInfoSheet(alerts: weather.alerts.displayInfos)
    }
}

extension AlertResponse {
    /// Unified card models, active-first — the badge (AlertView) and the sheet
    /// share this so the badge always headlines the sheet's top card.
    var displayInfos: [WeatherAlertInfo] {
        let infos: [WeatherAlertInfo] =
            switch self {
            case .canadian(let canadianAlerts):
                canadianAlerts
                    .flatMap { $0.alert?.alerts ?? [] }
                    .map(WeatherAlertInfo.init(canadianAlert:))
            case .oscar(let oscarAlerts):
                oscarAlerts.alerts.map(WeatherAlertInfo.init(pointAlert:))
            }
        return infos.sortedForDisplay()
    }
}

extension WeatherAlertInfo {
    /// EC's app API has no CAP severity; rank from alert type.
    init(
        canadianAlert alert: Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayloadPayload
            .alertPayload.alertsPayloadPayload
    ) {
        let banner = alert.alertBannerText ?? String(localized: "Wetterwarnung")
        id = alert.alertId ?? "\(banner)-\(alert.eventOnsetTime ?? "")"
        source = "ec"
        senderName = nil
        event = banner
        severityRank = switch (alert._type ?? "").lowercased() {
        case "warning": 3
        case "watch": 2
        default: 1
        }
        headline = nil
        details = alert.text
        instruction = nil
        onset = Self.parseISO8601(alert.eventOnsetTime)
        expires = Self.parseISO8601(alert.eventEndTime)
    }

    private static func parseISO8601(_ string: String?) -> Date? {
        string.flatMap(PrecipSeriesDate.parse)
    }
}
