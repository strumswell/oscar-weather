//
//  AlertView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import SwiftUI

struct AlertView: View {
    @State private var isAlterSheetPresented = false
    @Environment(Weather.self) private var weather: Weather
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .foregroundColor(.orange)
                .frame(width: 15, height: 15)
            if hasAlert() {
                Text(getFormattedHeadline())
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .bold()
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(.orange, lineWidth: 2)
        )
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            isAlterSheetPresented.toggle()
        }
        .sheet(isPresented: $isAlterSheetPresented) {
            AlertListView()
        }
        .padding(.top, -10)
        .shadow(radius: 15)
    }
}

extension AlertView {
    func hasAlert() -> Bool {
        return (weather.alerts.alerts?.count ?? 0) > 0
    }
    
    func getAlertCont() -> Int {
        return weather.alerts.alerts?.count ?? 0
    }
    
    func getFormattedHeadline() -> String {
        let langStr = Locale.current.language.languageCode?.identifier ?? "de"
        let alertCount = getAlertCont()
        let headlineDe = (weather.alerts.alerts?.first?.headline_de ?? "")
            .replacingOccurrences(of: "Amtliche", with: "")
            .replacingOccurrences(of: "UNWETTER", with: "")
        let headlineEn = (weather.alerts.alerts?.first?.event_en ?? "")
            .replacingOccurrences(of: "Official", with: "")
        let localizedEvent = langStr == "de"
            ? headlineDe.uppercased()
            : headlineEn.uppercased()
        
        if alertCount > 1 {
            return "\(localizedEvent) (+\(alertCount-1))"
        } else {
            return localizedEvent
        }
        
    }
}
