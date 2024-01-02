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
            List(weather.alerts , id: \.self) { alert in
                AlertDetailView(alert: alert)
            }
            .navigationBarTitle(Text("Unwetterwarnungen"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button("Fertig", action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
        }
    }
}

struct AlertDetailView: View {
    var alert: Components.Schemas.Alert
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundColor(.orange)
                    .frame(width: 15, height: 15)
                Text(alert.event ?? "")
                    .font(.title3)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 1)
            
            HStack {
                Text("Start: " + alert.getStartDate())
                    .font(.subheadline)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            HStack {
                Text("Ende: " + alert.getEndDate())
                    .font(.subheadline)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }
            .padding(.bottom, 1.5)

            HStack {
                Text(alert.descriptionText ?? "")
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
