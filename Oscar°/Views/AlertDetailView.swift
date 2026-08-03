//
//  AlertDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 01.12.21.
//

import SwiftUI

struct AlertListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        NavigationStack {
            List {
                switch weather.alerts {
                case .canadian(let canadianAlerts):
                    let alerts = canadianAlerts.flatMap { $0.alert?.alerts ?? [] }
                    ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                        AlertDetailView(alert: .canadian([alert]))
                    }
                case .oscar(let oscarAlerts):
                    ForEach(oscarAlerts.alerts, id: \.alertId) { alert in
                        AlertDetailView(alert: .oscar(alert))
                    }
                }
            }
            .navigationTitle("Unwetterwarnungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing, content: {
                    Button(role: .close) {
                        dismiss()
                        UIApplication.shared.playHapticFeedback()
                    }
                })
            })
        }
    }
}

struct AlertDetailView: View {
    enum AlertType {
        case canadian(Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayloadPayload.alertPayload.alertsPayload)
        case oscar(OscarPointAlert)
    }
    
    var alert: AlertType
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.orange)
                    .frame(width: 15, height: 15)
                Text(getHeadline())
                    .font(.headline)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 1)
            
            HStack {
                Text("Start: \(getStartDate())")
                    .font(.subheadline)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            HStack {
                Text("Ende: \(getEndDate())")
                    .font(.subheadline)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            .padding(.bottom, 1.5)

            HStack {
                Text(getDescription())
                    .font(.subheadline)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            .padding(.bottom, 1.5)
            
            if let instruction = getInstruction() {
                HStack {
                    Text(instruction)
                        .font(.subheadline)
                        .minimumScaleFactor(0.5)
                    Spacer()
                }
                .padding(.bottom, 1)
            }

            HStack {
                Text("Quelle: \(getSource())")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding([.top, .bottom])
    }
}

extension AlertDetailView {
    func getStartDate() -> String {
        switch alert {
        case .canadian(let canadianAlert):
            if let dateString = canadianAlert.first?.eventOnsetTime {
                return parseISO8601Date(dateString).map(formatDate) ?? String(localized: "Unbekannt")
            } else {
                return String(localized: "Unbekannt")
            }
        case .oscar(let oscarAlert):
            return oscarAlert.onsetAt.map(formatDate) ?? String(localized: "Unbekannt")
        }
    }

    func getEndDate() -> String {
        switch alert {
        case .canadian(let canadianAlert):
            if let dateString = canadianAlert.first?.eventEndTime {
                return parseISO8601Date(dateString).map(formatDate) ?? String(localized: "Unbekannt")
            } else {
                return String(localized: "Unbekannt")
            }
        case .oscar(let oscarAlert):
            return oscarAlert.expiresAt.map(formatDate) ?? String(localized: "Unbekannt")
        }
    }
    
    func formatDate(date: Date) -> String {
        SettingService.formattedDateTime(date)
    }
    
    func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
    
    func getHeadline() -> String {
        switch alert {
        case .canadian(let canadianAlert):
            return canadianAlert.first?.alertBannerText ?? ""
        case .oscar(let oscarAlert):
            return oscarAlert.event
        }
    }

    func getDescription() -> String {
        switch alert {
        case .canadian(let canadianAlert):
            return canadianAlert.first?.text ?? ""
        case .oscar(let oscarAlert):
            return oscarAlert.description ?? ""
        }
    }

    func getInstruction() -> String? {
        switch alert {
        case .canadian:
            return nil
        case .oscar(let oscarAlert):
            return oscarAlert.instruction
        }
    }

    func getSource() -> String {
        switch alert {
        case .canadian:
            return "Environment Canada"
        case .oscar(let oscarAlert):
            switch oscarAlert.source {
            case "nws": return "NOAA / National Weather Service"
            case "cwa": return "CWA / Central Weather Administration"
            case "meteoalarm":
                // Meteoalarm only aggregates — name the originating national
                // service when the server identifies it.
                if let sender = oscarAlert.senderName {
                    return "\(sender) · EUMETNET Meteoalarm"
                }
                return "EUMETNET Meteoalarm"
            default: return "Deutscher Wetterdienst"
            }
        }
    }
}
