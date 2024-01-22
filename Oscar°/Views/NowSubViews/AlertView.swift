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
        .shadow(radius: 15)
    }
}
