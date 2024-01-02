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
            if (weather.alerts.count > 1) {
                Text(weather.alerts.first!.getFormattedHeadline().uppercased() + " (+"+String(weather.alerts.count-1)+")")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .bold()
            } else if (weather.alerts.count > 0) {
                Text(weather.alerts.first!.getFormattedHeadline().uppercased())
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
    }
}

extension Components.Schemas.Alert {
    func getFormattedHeadline() -> String {
        guard let headline = headline else {
            return ""
        }

        return headline
            .replacingOccurrences(of: "Amtliche", with: "")
            .replacingOccurrences(of: "UNWETTER", with: "")
    }
    
    public func getStartDate() -> String {
        return formatDate(time: self.start ?? 0.0)
    }
    
    public func getEndDate() -> String {
        return formatDate(time: self.end ?? 0.0)
    }
    
    public func formatDate(time: Double) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(Int(time) / 1000))
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "de")
        return dateFormatter.string(from: date)
    }
}
