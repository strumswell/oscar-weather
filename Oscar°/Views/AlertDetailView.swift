//
//  AlertDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 01.12.21.
//

import SwiftUI

struct AlertListView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(Weather.self) private var weather: Weather
    
    var body: some View {
        NavigationView {
            List {
                switch weather.alerts {
                case .brightsky(let brightskyAlerts):
                    ForEach(brightskyAlerts.alerts ?? [], id: \.self) { alert in
                        AlertDetailView(alert: .brightsky(alert))
                    }
                case .canadian(let canadianAlerts):
                    if let firstAlert = canadianAlerts.first?.alert?.alerts {
                        AlertDetailView(alert: .canadian(firstAlert))
                    }
                }
            }
            .navigationBarTitle(Text("Unwetterwarnungen"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button(String(localized: "Fertig"), action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
        }
    }
}

struct AlertDetailView: View {
    enum AlertType {
        case brightsky(Components.Schemas.WeatherAlert)
        case canadian(Operations.getCanadianWeatherAlerts.Output.Ok.Body.jsonPayloadPayload.alertPayload.alertsPayload)
    }
    
    var alert: AlertType
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundColor(.orange)
                    .frame(width: 15, height: 15)
                Text(getHeadline())
                    .font(.headline)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 1)
            
            HStack {
                Text("Start: " + getStartDate())
                    .font(.subheadline)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            HStack {
                Text("Ende: " + getEndDate())
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
                Text("Quelle: " + getSource())
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
        case .brightsky(let brightskyAlert):
            return formatDate(date: brightskyAlert.onset ?? Date())
        case .canadian(let canadianAlert):
            if let dateString = canadianAlert.first?.eventOnsetTime {
                return formatDate(date: parseISO8601Date(dateString) ?? Date())
            } else {
                return formatDate(date: Date())
            }
        }
    }
    
    func getEndDate() -> String {
        switch alert {
        case .brightsky(let brightskyAlert):
            return formatDate(date: brightskyAlert.expires ?? Date())
        case .canadian(let canadianAlert):
            if let dateString = canadianAlert.first?.eventEndTime {
                return formatDate(date: parseISO8601Date(dateString) ?? Date())
            } else {
                return formatDate(date: Date())
            }
        }
    }
    
    func formatDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de")
        return dateFormatter.string(from: date)
    }
    
    func parseISO8601Date(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
    
    func getHeadline() -> String {
        switch alert {
        case .brightsky(let brightskyAlert):
            return brightskyAlert.event_de ?? brightskyAlert.event_en ?? ""
        case .canadian(let canadianAlert):
            return canadianAlert.first?.alertBannerText ?? ""
        }
    }
    
    func getDescription() -> String {
        switch alert {
        case .brightsky(let brightskyAlert):
            return brightskyAlert.description_de ?? brightskyAlert.description_en ?? ""
        case .canadian(let canadianAlert):
            return canadianAlert.first?.text ?? ""
        }
    }
    
    func getInstruction() -> String? {
        switch alert {
        case .brightsky(let brightskyAlert):
            return brightskyAlert.instruction_de ?? brightskyAlert.instruction_en
        case .canadian:
            return nil
        }
    }
    
    func getSource() -> String {
        switch alert {
        case .brightsky:
            return "Deutscher Wetterdienst"
        case .canadian:
            return "Environment Canada"
        }
    }
}
