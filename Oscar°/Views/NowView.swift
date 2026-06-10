//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI
import OpenAPIRuntime
import OpenAPIURLSession
import MapKit
import WidgetKit

#Preview {
    NowView().preferredColorScheme(.dark)
}

struct NowView: View {
    private let settingsService = SettingService.shared
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Namespace private var sheetTransition
    @State private var tapCount = 0
    @State private var presentation = NowPresentationCoordinator()
    @State private var oscarRadarState = OscarRadarState(renderMode: .preview)
    @State private var gfsImageState = GFSImageLayerState(renderMode: .preview)

    var body: some View {
        ZStack {
            WeatherSimulationView(animationsPaused: presentation.sheet != nil)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack(alignment: .leading) {
                        
                        HeadView(locationTransition: sheetTransition)
                            .padding(.top, 50)
                            .onTapGesture {
                                self.tapCount += 1
                                if self.tapCount == 10 {
                                    self.tapCount = 0  // Reset the count if needed
                                    weather.debug.toggle()
                                    UIApplication.shared.playHapticFeedback()
                                }
                            }
                        RainView(openRadarMap: openRadarMap)
                            .opacity(weather.isLoading && !weather.hasContent ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
                        HourlyView()
                        DailyView()
                        VStack(alignment: .leading) {
                            Text("Karte")
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                                .padding([.leading, .top])
                                .onTapGesture {
                                    presentMap()
                                }
                            RadarView(
                                settingsService: settingsService,
                                showLayerSettings: false,
                                userActionAllowed: false,
                                showWindParticles: false,
                                oscarRadarState: oscarRadarState,
                                gfsImageState: gfsImageState
                            )
                                .frame(height: 350)
                                .cornerRadius(10)
                                .padding()
                                .opacity(weather.isLoading && !weather.hasContent ? 0.3 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
                                .onTapGesture {
                                    presentMap()
                                }
                                .task {
                                    if settingsService.oscarRadarLayer {
                                        await oscarRadarState.loadCurrentFrame()
                                    } else if let layer = settingsService.activeTileLayer {
                                        await gfsImageState.loadLayer(layer)
                                    }
                                }
                                .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
                                    if isEnabled {
                                        gfsImageState.pause()
                                        if oscarRadarState.frames.isEmpty {
                                            Task { await oscarRadarState.loadCurrentFrame() }
                                        }
                                    } else {
                                        oscarRadarState.pause()
                                    }
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

                        AQIView()
                        LegalTextView()
                        if weather.debug {
                            VStack {
                                Text(weather.isLoading.description)
                                Text(weather.error)
                                Text("Air")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.air))
                                Text("Radar")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.radar))
                                Text("Alerts")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.alerts))
                                Text("Time")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.time))
                                Text("Location")
                                    .padding(.top, 20)
                                Text(String(reflecting: location.coordinates))
                                Text(String(reflecting: location.name))
                                Text("Forecast")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.forecast))
                            }
                        }
                    }
                }
            }
            .padding(.top, 40)
            .refreshable {
                await weather.refresh(location: location)
            }
        }
        .environment(presentation)
        .sheet(item: $presentation.sheet) { sheet in
            NowSheetView(
                sheet: sheet,
                settingsService: settingsService,
                locationTransition: sheetTransition
            )
        }
        .background(.thinMaterial)
        .edgesIgnoringSafeArea(.all)
        .task {
            // Periodically refresh radar / tile metadata so the map stays current.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { break }
                if settingsService.oscarRadarLayer {
                    await oscarRadarState.loadCurrentFrame()
                } else if settingsService.activeTileLayer != nil {
                    if let layer = settingsService.activeTileLayer { await gfsImageState.loadLayer(layer) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
                WidgetCenter.shared.reloadAllTimelines()
                if settingsService.oscarRadarLayer {
                    await oscarRadarState.loadCurrentFrame()
                } else if settingsService.activeTileLayer != nil {
                    if let layer = settingsService.activeTileLayer { await gfsImageState.loadLayer(layer) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changedLocation, object: nil)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cityToggle, object: nil)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unitChanged, object: nil)) { _ in
            Task {
                await weather.refresh(location: location)
            }
        }
    }
}

extension NowView {
    private func presentMap() {
        UIApplication.shared.playHapticFeedback()
        presentation.present(.map)
    }

    private func openRadarMap() {
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = false
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        settingsService.oscarRadarLayer = true
        gfsImageState.pause()
        presentMap()
    }
}
