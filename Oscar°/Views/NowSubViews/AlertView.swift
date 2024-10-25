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
        switch weather.alerts {
        case .brightsky(let brightskyAlerts):
            return (brightskyAlerts.alerts?.count ?? 0) > 0
        case .canadian(let canadianAlerts):
            return !canadianAlerts.isEmpty && canadianAlerts.first?.alert != nil
        }
    }
    
    func getAlertCount() -> Int {
        switch weather.alerts {
        case .brightsky(let brightskyAlerts):
            return brightskyAlerts.alerts?.count ?? 0
        case .canadian(let canadianAlerts):
            return canadianAlerts.reduce(0) { $0 + ($1.alert?.alerts?.count ?? 0) }
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
        }
    }
}
