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
        HStack(spacing: 5) {
            // The icon alone carries the warning color; the glass capsule and
            // primary text keep the pill in the app's Liquid Glass language —
            // a solid orange fill read as a massive block over the sky gradient.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            if hasAlert() {
                Text(getFormattedHeadline())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(.orange.opacity(0.5)), in: Capsule())
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            presentation.present(.alerts)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Öffnet die Wetterwarnungen"))
        .accessibilityAction {
            UIApplication.shared.playHapticFeedback()
            presentation.present(.alerts)
        }
        .padding(.top, -10)
    }
}

extension AlertView {
    func hasAlert() -> Bool {
        switch weather.alerts {
        case .brightsky(let brightskyAlerts):
            return (brightskyAlerts.alerts?.count ?? 0) > 0
        case .canadian(let canadianAlerts):
            return !canadianAlerts.isEmpty && canadianAlerts.first?.alert != nil
        case .oscar(let oscarAlerts):
            return !oscarAlerts.alerts.isEmpty
        }
    }

    func getAlertCount() -> Int {
        switch weather.alerts {
        case .brightsky(let brightskyAlerts):
            return brightskyAlerts.alerts?.count ?? 0
        case .canadian(let canadianAlerts):
            return canadianAlerts.reduce(0) { $0 + ($1.alert?.alerts?.count ?? 0) }
        case .oscar(let oscarAlerts):
            return oscarAlerts.alerts.count
        }
    }

    func getFormattedHeadline() -> String {
        switch weather.alerts {
        case .brightsky(let brightskyAlerts):
            let alertCount = getAlertCount()
            let headlineDe = (brightskyAlerts.alerts?.first?.headline_de ?? "")
                .replacingOccurrences(of: "Amtliche", with: "")
                .replacingOccurrences(of: "UNWETTER", with: "")
            let localizedEvent = headlineDe.uppercased()
            
            if alertCount > 1 {
                return "\(localizedEvent) (+\(alertCount-1))"
            } else {
                return localizedEvent
            }
        case .canadian(let canadianAlerts):
            let alertCount = getAlertCount()
            if let firstAlert = canadianAlerts.first?.alert?.alerts?.first {
                let headline = firstAlert.alertBannerText?.uppercased() ?? ""
                if alertCount > 1 {
                    return "\(headline) (+\(alertCount-1))"
                } else {
                    return headline
                }
            }
            return ""
        case .oscar(let oscarAlerts):
            // NWS headlines are long provenance sentences; the event name is the
            // badge-sized label ("SEVERE THUNDERSTORM WARNING").
            let alertCount = getAlertCount()
            let event = (oscarAlerts.alerts.first?.event ?? "").uppercased()
            if alertCount > 1 {
                return "\(event) (+\(alertCount-1))"
            } else {
                return event
            }
        }
    }
}
