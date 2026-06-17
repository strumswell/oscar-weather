//
//  MapDetailView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 28.01.22.
//

import SwiftUI

struct MapDetailView: View {
    let settingsService: SettingService
    @Environment(\.presentationMode) var presentationMode
    @State private var oscarRadarState = OscarRadarState(renderMode: .fullscreen)
    @State private var gfsImageState = GFSImageLayerState(renderMode: .fullscreen)

    var body: some View {
        NavigationView {
            ZStack {
                RadarView(
                    settingsService: settingsService,
                    showLayerSettings: true,
                    oscarRadarState: oscarRadarState,
                    gfsImageState: gfsImageState
                )

                // Timeline controls — floats above the bottom safe area
                VStack {
                    Spacer()
                    if settingsService.oscarRadarLayer {
                        OscarRadarTimelineControls(radarState: oscarRadarState)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                    } else if settingsService.activeTileLayer != nil {
                        WeatherTileTimelineControls(imageState: gfsImageState)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 60)
                    }
                }
            }
            .ignoresSafeArea(edges: [.bottom])
            .navigationBarTitle(Text("Karte"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Fertig")) {
                        oscarRadarState.pause()
                        gfsImageState.pause()
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    }
                }
            }
            .task {
                if settingsService.oscarRadarLayer {
                    oscarRadarState.setRegion(settingsService.oscarRadarRegion)
                    await oscarRadarState.loadAllFrames()
                } else if let layer = settingsService.activeTileLayer {
                    await gfsImageState.loadLayer(layer)
                }
            }
            .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
                if isEnabled {
                    gfsImageState.pause()
                    oscarRadarState.setRegion(settingsService.oscarRadarRegion)
                    if oscarRadarState.frames.isEmpty {
                        Task { await oscarRadarState.loadAllFrames() }
                    }
                } else {
                    oscarRadarState.pause()
                }
            }
            .onChange(of: settingsService.oscarRadarRegion) { _, newRegion in
                guard settingsService.oscarRadarLayer else { return }
                oscarRadarState.setRegion(newRegion)
                Task { await oscarRadarState.reloadForCurrentRegion() }
            }
            .onChange(of: settingsService.activeTileLayer) { _, newLayer in
                if let layer = newLayer {
                    oscarRadarState.pause()
                    Task { await gfsImageState.loadLayer(layer) }
                } else {
                    gfsImageState.pause()
                }
            }
        }
    }
}
