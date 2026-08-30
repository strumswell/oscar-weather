//
//  AlertView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import SwiftUI

struct AlertView: View {
    let additionalMeteorEvent: MeteorShowerEvent?

    @Environment(Weather.self) private var weather: Weather
    @Environment(NowPresentationCoordinator.self) private var presentation

    init(additionalMeteorEvent: MeteorShowerEvent? = nil) {
        self.additionalMeteorEvent = additionalMeteorEvent
    }

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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                    if let top = alerts.first {
                        Text(formattedHeadline(top: top, count: alerts.count))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, additionalMeteorEvent == nil ? 10 : 7)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("now.alert.weather")
            .accessibilityHint(Text("Öffnet die Wetterwarnungen"))

            if let event = additionalMeteorEvent {
                Rectangle()
                    .fill(.primary.opacity(0.16))
                    .frame(width: 1, height: 18)
                    .accessibilityHidden(true)

                Button {
                    UIApplication.shared.playHapticFeedback()
                    presentation.present(.meteorShower(event))
                } label: {
                    Text("+1")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 10)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("now.alert.meteor")
                .accessibilityLabel(Text(MeteorShowerCopy.bannerText(for: event.presentation)))
                .accessibilityHint(
                    Text(String(
                        localized: "meteor.accessibility.hint",
                        defaultValue: "Öffnet Details zum Sternschnuppenschauer"
                    ))
                )
            }
        }
        // Keep the visual capsule as slim as the original alert pill while
        // both halves retain a comfortable 44-point tap target.
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
        UIApplication.shared.playHapticFeedback()
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
