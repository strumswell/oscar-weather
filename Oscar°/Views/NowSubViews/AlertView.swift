//
//  AlertView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 21.02.22.
//

import SwiftUI

struct AlertView: View {
    @Binding var alerts: [DWDAlert]?
    @State private var isAlterSheetPresented = false
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .resizable()
                .foregroundColor(.orange)
                .frame(width: 15, height: 15)
            if (alerts!.count > 1) {
                Text((alerts?.first?.getFormattedHeadline().uppercased() ?? "...") + " (+"+String(alerts!.count-1)+")")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .bold()
            } else {
                Text(alerts?.first?.getFormattedHeadline().uppercased() ?? "...")
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
            AlertListView(alerts: $alerts)
        }
        .padding(.top, -10)
    }
}
