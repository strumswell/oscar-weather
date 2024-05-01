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
            List(weather.alerts.alerts ?? [] , id: \.self) { alert in
                AlertDetailView(alert: alert)
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
    var alert: Components.Schemas.WeatherAlert
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
            
            HStack {
                Text(getInstruction())
                    .font(.subheadline)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            .padding(.bottom, 1)

            HStack {
                Text("Quelle: Deutscher Wetterdienst")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding([.top, .bottom])
    }
}

extension AlertDetailView {
    public func getStartDate() -> String {
        return formatDate(date: alert.onset ?? Date())
    }
    
    public func getEndDate() -> String {
        return formatDate(date: alert.expires ?? Date())
    }
    
    public func formatDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de")
        return dateFormatter.string(from: date)
    }
    
    public func getHeadline() -> String {
        let langStr = Locale.current.language.languageCode?.identifier ?? "de"
        let headlineDe = alert.event_de ?? ""
        let headlineEn = (alert.event_en ?? "").capitalized
        let localizedEvent = langStr == "de" ? headlineDe : headlineEn
        return localizedEvent
    }
    
    public func getDescription() -> String {
        let langStr = Locale.current.language.languageCode?.identifier ?? "de"
        let descriptionDe = alert.description_de ?? ""
        let descriptionEn = alert.description_en ?? ""
        let localizedDescription = langStr == "de" ? descriptionDe : descriptionEn
        return localizedDescription
    }
    
    public func getInstruction() -> String {
        let langStr = Locale.current.language.languageCode?.identifier ?? "de"
        let instructionDe = alert.instruction_de ?? ""
        let instructionEn = alert.instruction_en ?? ""
        let localizedInstruction = langStr == "de" ? instructionDe : instructionEn
        return localizedInstruction
    }
}
