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
    @State private var isMapSheetPresented = false
    @State private var tapCount = 0
    @State private var skyIsVisible = true
    @State private var oscarRadarState = OscarRadarState(renderMode: .preview)
    @State private var gfsImageState = GFSImageLayerState(renderMode: .preview)

    var body: some View {
        ZStack {
            WeatherSimulationView(animationsPaused: !skyIsVisible)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack(alignment: .leading) {
                        
                        HeadView()
                            .padding(.top, 50)
                            .onScrollVisibilityChange(threshold: 0.1) { visible in
                                skyIsVisible = visible
                            }
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

            if weather.isLoading && weather.hasContent {
                RefreshPill()
                    // Scale is declared on the pill itself so the spring
                    // pops it in place instead of scaling the whole overlay.
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    // The ZStack ignores the safe area; keep the pill just
                    // below the status bar / Dynamic Island.
                    .padding(.top, topSafeAreaInset + 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: weather.isLoading && weather.hasContent)
        .sheet(isPresented: $isMapSheetPresented) {
            MapDetailView(settingsService: settingsService)
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
    private var topSafeAreaInset: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window?.safeAreaInsets.top ?? 59
    }

    private func presentMap() {
        UIApplication.shared.playHapticFeedback()
        isMapSheetPresented = true
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

/// Small breathing pill shown while fresh data loads behind
/// already-visible (cached) content. Sits just below the Dynamic Island.
///
/// Two superimposed sine waves (slightly detuned, so the pattern never
/// visibly repeats) drive the width; the opacity and glow trail the width
/// by a third of a breath. That phase lag is what makes it feel organic
/// instead of ticking back and forth. Never fades out fully.
private struct RefreshPill: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathWave = sin(t * 2 * .pi / 2.8)
            let driftWave = sin(t * 2 * .pi / 7.3 + 1.2)
            let breath = 0.5 + 0.5 * (breathWave * 0.85 + driftWave * 0.15)
            let glow = 0.5 + 0.5 * sin(t * 2 * .pi / 2.8 - .pi / 3)

            Capsule()
                .fill(.white)
                .frame(width: 34 + 34 * breath, height: 4.5)
                .opacity(0.28 + 0.38 * glow)
                .shadow(color: .white.opacity(0.20 + 0.30 * glow), radius: 5)
        }
    }
}
