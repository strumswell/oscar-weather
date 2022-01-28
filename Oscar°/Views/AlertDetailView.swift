//
//  AlertDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 01.12.21.
//

import SwiftUI

struct AlertListView: View {
    @Binding var alerts: [AWAlert]?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List(alerts ?? [], id: \.self) { alert in
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
    var alert: AWAlert
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundColor(.red.opacity(0.7))
                    .frame(width: 15, height: 15)
                Text(alert.description.localized)
                    .font(.title3)
                    .bold()
                Spacer()
            }
            .padding(.bottom, 1)
            
            HStack {
                Text(alert.area.first?.summary.components(separatedBy: "Quelle:")[0] ?? "")
                    .font(.body)
                    .lineLimit(5)
                    .minimumScaleFactor(0.5)
                Spacer()
            }

            HStack {
                Text("Quelle: " + (alert.area.first?.summary ?? "").components(separatedBy: "Quelle:")[1])
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding([.top, .bottom])
    }
}
