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
        let tint = alerts.first.map {
            AlertSeverityStyle.color(rank: $0.severityRank, source: $0.source)
        } ?? .orange
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
        .padding(.vertical, 6)
        .background(tint.opacity(0.52), in: Capsule())
        .cardBackground(in: Capsule())
        .cardBorder(Capsule())
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .accessibilityIdentifier("now.alert")
        .onTapGesture {
            presentation.present(.alerts)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Öffnet die Wetterwarnungen"))
        .accessibilityAction {
            presentation.present(.alerts)
        }
    }
}

extension AlertView {
    func formattedHeadline(top: WeatherAlertInfo, count: Int) -> String {
        let event = top.event.localizedUppercase
        return count > 1 ? "\(event) (+\(count - 1))" : event
    }
}
