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
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var sheetTransition
    @State private var tapCount = 0
    @State private var presentation = NowPresentationCoordinator()
    @State private var atmosphereDebug = AtmosphereDebugState()
    @State private var modelGridState = ModelGridLayerState(renderMode: .preview)
    @State private var manualRefreshInFlight = false
    @State private var showRefreshIndicator = false
    @State private var spinnerShownAt: Date?
    @State private var modelFallbackToast: String?

    var body: some View {
        // Drive the pull-down spinner only while the scene is actually active. Coming
        // back from the background, `willEnterForeground` starts a refresh before the app
        // is on-screen; if we debounced from that moment, the spinner's whole show/hide
        // cycle could play out during the invisible transition and the user would catch
        // only its tail — a jump as the view snapped back up. Gating on `.active` measures
        // the debounce from when the app is visible, so a refresh that finishes around the
        // time the app appears shows no spinner, and a genuinely slow one shows a full,
        // on-screen cycle.
        let spinnerPending = weather.isLoading && weather.hasContent && !manualRefreshInFlight && scenePhase == .active

        ZStack {
            WeatherSimulationView(isCoveredBySheet: presentation.sheet != nil || presentation.isMapPresented)
            if weather.hasContent {
            ScrollView(.vertical) {
                ZStack {
                    VStack(alignment: .leading) {
                        if showRefreshIndicator {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(UIColor.label))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
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
                        HourlyView()
                        DailyView()
                        VStack(alignment: .leading) {
                            Button(action: presentMap) {
                                Text("Karte")
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(Color(UIColor.label))
                                    .padding([.leading, .top])
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Öffnet die Karte"))
                            WeatherMapPreview(
                                settingsService: settingsService,
                                modelGridState: modelGridState
                            )
                                .frame(height: 350)
                                .clipShape(.rect(cornerRadius: 10))
                                .padding()
                                .onTapGesture {
                                    presentMap()
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(Text("Regenradar"))
                                .accessibilityHint(Text("Öffnet die Karte"))
                                .accessibilityAction { presentMap() }
                                .task {
                                    if let layer = settingsService.activeTileLayer {
                                        await modelGridState.loadLayer(layer)
                                    }
                                }
                                .onChange(of: settingsService.activeTileLayer) { _, newLayer in
                                    if let layer = newLayer {
                                        Task { await modelGridState.loadLayer(layer) }
                                    } else {
                                        modelGridState.pause()
                                    }
                                }
                        }

                        AQIView()
                        ClimateView()
                        LegalTextView()
                        if weather.debug {
                            VStack {
                                Text(weather.isLoading.description)
                                Text("spinner=\(showRefreshIndicator.description) pending=\(spinnerPending.description)")
                                Text(weather.error)
                                Text("Air")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.air))
                                Text("Radar")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.precipSeries))
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
                    .animation(.easeInOut(duration: 0.3), value: showRefreshIndicator)
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 40)
            .refreshable {
                // Run the refresh in an unstructured task so it doesn't inherit the
                // pull-to-refresh gesture's cancellation. SwiftUI cancels the
                // `.refreshable` action task when the refresh control resolves, which
                // would otherwise abort the still-in-flight radar/alerts requests
                // (forecast/air usually survive as cache hits) and discard good data.
                manualRefreshInFlight = true
                await Task { await weather.refresh(location: location) }.value
                manualRefreshInFlight = false
            }
            .task(id: spinnerPending) {
                guard spinnerPending else {
                    // Loading finished, or the scene left `.active`. If the spinner is
                    // showing, hold it for a minimum on-screen time before hiding, so a
                    // slow refresh that finishes just after the debounce reads as a clean
                    // spinner rather than a brief flash. `try?` lets the hide run even if
                    // this task is cancelled mid-hold, so the indicator can never get
                    // stranded on.
                    if showRefreshIndicator, let shownAt = spinnerShownAt {
                        let remaining = 0.6 - Date.now.timeIntervalSince(shownAt)
                        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                    }
                    showRefreshIndicator = false
                    spinnerShownAt = nil
                    return
                }
                // Debounce: only show the spinner if loading lingers past 500ms of
                // on-screen time, so quick (cache-hit) refreshes don't flash it.
                guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
                // If loading finishes right at the debounce boundary, the sleep's timer
                // can win the race against cancellation and resume normally even though
                // the id already flipped to `false` and the replacement (hide) task has
                // already run. Showing the spinner then would strand it on screen — the
                // id won't change again, so nothing would ever hide it. `spinnerPending`
                // is captured at body time (always `true` here) and can't catch this;
                // the cancellation flag is set either way, so check it explicitly.
                guard !Task.isCancelled else { return }
                spinnerShownAt = .now
                showRefreshIndicator = true
            }
            } else if weather.loadState == .failed {
                // Cold start with no cached forecast and a failed fetch: offer a retry over the
                // twilight backdrop instead of an empty screen (the all-zero forecast used to
                // stand in here). `loadState` latches `.failed` so a re-triggered refresh that
                // clears `error` can't flicker this away. Later errors keep last-known-good.
                WeatherUnavailableView(isRetrying: weather.isLoading) {
                    Task { await weather.refresh(location: location) }
                }
            }
            if weather.debug {
                AtmosphereDebugPanel(state: atmosphereDebug)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
            }

            if let message = modelFallbackToast, presentation.sheet == nil, !presentation.isMapPresented {
                ToastBanner(message: message)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
                    .task {
                        // Start the dismiss timer only once the toast is actually on screen
                        // (e.g. after the settings sheet that triggered the change is closed).
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.easeInOut(duration: 0.3)) { modelFallbackToast = nil }
                    }
            }
        }
        .environment(presentation)
        .environment(atmosphereDebug)
        .sheet(item: $presentation.sheet) { sheet in
            NowSheetView(
                sheet: sheet,
                settingsService: settingsService,
                locationTransition: sheetTransition
            )
        }
        .fullScreenCover(isPresented: $presentation.isMapPresented) {
            WeatherMapDetailView(settingsService: settingsService) {
                presentation.isMapPresented = false
            }
        }
        .background(.thinMaterial)
        .edgesIgnoringSafeArea(.all)
        .task {
            // Testing hook: `-autoPresentMapLibreAfter <seconds>` opens the map AFTER
            // the NowView (incl. the preview card's map) exists — reproduces the
            // tap-to-open flow headless, unlike -autoPresentMap which presents at launch.
            let mapLibreDelay = UserDefaults.standard.double(forKey: "autoPresentMapLibreAfter")
            if mapLibreDelay > 0 {
                Task {
                    try? await Task.sleep(for: .seconds(mapLibreDelay))
                    presentation.isMapPresented = true
                }
            }
            // Periodically refresh the tile-layer metadata so the map preview stays
            // current (the radar preview refreshes itself inside WeatherMapPreview).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { break }
                if settingsService.activeTileLayer != nil { await modelGridState.refreshIfStale() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
                await WidgetBasemapRenderer.refreshIfNeeded()
                WidgetCenter.shared.reloadAllTimelines()
                if settingsService.activeTileLayer != nil { await modelGridState.refreshIfStale() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .changedLocation, object: nil)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
                await WidgetBasemapRenderer.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cityToggle, object: nil)) { _ in
            Task {
                await weather.refresh(location: location)
                await NotificationSettingsManager.shared.syncLocationUpdate()
                await WidgetBasemapRenderer.refreshIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unitChanged, object: nil)) { _ in
            // Clear any stale fallback notice; the upcoming refresh re-posts one if it still applies.
            modelFallbackToast = nil
            Task {
                await weather.refresh(location: location)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forecastModelFallback)) { _ in
            withAnimation(.spring(duration: 0.4)) {
                modelFallbackToast = String(localized: "Außerhalb des Modells – Automatik aktiv.")
            }
        }
    }
}

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(UIColor.label))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .accessibilityElement()
            .accessibilityLabel(Text(message))
    }
}

/// Shown over the twilight backdrop on a cold start when no forecast could be loaded and
/// nothing is cached. Offers a retry; background observers also keep retrying on their own.
private struct WeatherUnavailableView: View {
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Wetter nicht verfügbar", systemImage: "cloud.slash")
        } description: {
            Text("Die Wetterdaten konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.")
        } actions: {
            Button(action: retry) {
                if isRetrying {
                    ProgressView()
                } else {
                    Text("Erneut versuchen")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying)
        }
    }
}

extension NowView {
    private func presentMap() {
        UIApplication.shared.playHapticFeedback()
        presentation.isMapPresented = true
    }

    private func openRadarMap() {
        settingsService.activeTileLayer = nil
        settingsService.settings?.rainviewerLayer = false
        settingsService.settings?.dwdLayer = false
        settingsService.save()
        settingsService.oscarRadarLayer = true
        modelGridState.pause()
        presentMap()
    }
}
