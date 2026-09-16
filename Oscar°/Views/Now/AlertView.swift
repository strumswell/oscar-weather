//
//  AlertView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import SwiftUI

struct AlertView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(NowPresentationCoordinator.self) private var presentation

    var body: some View {
        let alerts = weather.alerts.displayInfos
        // The wash carries the severity color the user knows from the map
        // polygons and the sheet chip ("vigilance jaune" tints yellow, red
        // stays red); the capsule wears the same material + sky wash +
        // hairline as the cards so it belongs to the scene.
        let tint = alerts.first.map {
            AlertSeverityStyle.color(rank: $0.severityRank, source: $0.source)
        } ?? .orange
        HStack(spacing: 0) {
            Button(action: openAlerts) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                    if let top = alerts.first {
                        Text(formattedHeadline(top: top, count: alerts.count))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("now.alert.weather")
            .accessibilityHint(Text("Öffnet die Wetterwarnungen"))
        }
        // Keep the visual capsule as slim as the original alert pill while
        // the button retains a comfortable 44-point tap target.
        .background {
            Capsule()
                .fill(tint.opacity(0.52))
                .cardBackground(in: Capsule())
                .cardBorder(Capsule())
                .frame(height: 28)
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private func openAlerts() {
        Haptics.impact()
        presentation.present(.alerts)
    }
}

extension AlertView {
    /// The event name is the badge-sized label ("SEVERE THUNDERSTORM WARNING");
    /// headlines are long provenance sentences.
    func formattedHeadline(top: WeatherAlertInfo, count: Int) -> String {
        let event = top.event.uppercased()
        return count > 1 ? "\(event) (+\(count - 1))" : event
    }
}
