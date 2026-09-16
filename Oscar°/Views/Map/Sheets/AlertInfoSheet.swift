//
//  AlertInfoSheet.swift
//  Oscar°
//
//  Warning sheet for tapped alert polygons (models: WeatherAlertInfo).
//

import CoreLocation
import SwiftUI
import UIKit
import simd

// MARK: - Models

// MARK: - DWD severity styling

// MARK: - Warning sheet

/// All warnings under the tapped point, active-first — presented small like
/// the Kartenebenen sheet, pullable to .large for long official texts.
struct AlertInfoSheet: View {
    let alerts: [WeatherAlertInfo]
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(alerts) { alert in
                        AlertInfoCard(alert: alert)
                    }
                    // Canadian alerts come straight from EC, not oscar-server.
                    if alerts.contains(where: { $0.source != "ec" }) {
                        PoweredByOscarServer(lockupHeight: 30)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle(alerts.count == 1 ? Text("Wetterwarnung") : Text("Wetterwarnungen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismissSheet() })
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
    }
}

private struct AlertInfoCard: View {
    let alert: WeatherAlertInfo

    private var severityColor: Color {
        AlertSeverityStyle.color(rank: alert.severityRank, source: alert.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(AlertSeverityStyle.label(rank: alert.severityRank, source: alert.source))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(severityColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(severityColor.opacity(0.16), in: Capsule())
                Spacer()
                Text("Stufe \(alert.severityRank)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(alert.headline ?? alert.event)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let validity {
                Label(validity, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let details = alert.details, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instruction = alert.instruction, !instruction.isEmpty {
                Divider()
                Text(instruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if let logo = AlertSeverityStyle.sourceLogo(alert.source) {
                    ProviderLogo(asset: logo, height: 18)
                }
                Text("Quelle: \(AlertSeverityStyle.sourceName(alert.source, senderName: alert.senderName))")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var validity: String? {
        switch (alert.onset, alert.expires) {
        case let (onset?, expires?):
            return "\(SettingService.formattedDateTime(onset)) – \(SettingService.formattedDateTime(expires))"
        case let (nil, expires?):
            return String(localized: "Bis \(SettingService.formattedDateTime(expires))")
        case let (onset?, nil):
            return String(localized: "Ab \(SettingService.formattedDateTime(onset))")
        default:
            return nil
        }
    }
}

// MARK: - Storm cell sheet
