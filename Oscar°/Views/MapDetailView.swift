//
//  MapDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 28.01.22.
//

import SwiftUI

struct MapDetailView: View {
    @ObservedObject var settingsService: SettingService
    @Environment(\.presentationMode) var presentationMode
    @State private var oscarRadarState = OscarRadarState()

    var body: some View {
        NavigationView {
            ZStack {
                RadarView(
                    settingsService: settingsService,
                    showLayerSettings: true,
                    oscarRadarState: oscarRadarState
                )

                // Compact player chip — floats above the bottom safe area
                VStack {
                    Spacer()
                    if settingsService.oscarRadarLayer {
                        OscarRadarTimelineControls(radarState: oscarRadarState)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                    }
                }
            }
            .ignoresSafeArea(edges: [.bottom])
            .navigationBarTitle(Text("Regenradar"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button(String(localized: "Fertig"), action: {
                        oscarRadarState.pause()
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
            .task {
                if settingsService.oscarRadarLayer {
                    await oscarRadarState.loadAllFrames()
                }
            }
            .onChange(of: settingsService.oscarRadarLayer) { oldValue, newValue in
                if newValue == true && oscarRadarState.frames.isEmpty {
                    Task { await oscarRadarState.loadAllFrames() }
                } else if newValue == false {
                    oscarRadarState.pause()
                }
            }
        }
    }
}
