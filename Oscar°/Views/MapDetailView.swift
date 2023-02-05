//
//  MapDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 28.01.22.
//

import SwiftUI

struct MapDetailView: View {
    @ObservedObject var now: NowViewModel
    @ObservedObject var settingsService: SettingService
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ZStack {
                RadarView(settingsService: settingsService, now: now, radarMetadata: $now.currentRadarMetadata, showLayerSettings: true)
            }
            .ignoresSafeArea(edges: [.bottom])
            .navigationBarTitle(Text("Karte"), displayMode: .inline)
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
