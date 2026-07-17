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
    NowView()
        .environment(Weather())
        .environment(Location())
        .environment(NowPresentationCoordinator())
        .preferredColorScheme(.dark)
}

struct NowView: View {
    private let settingsService = SettingService.shared
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(NowPresentationCoordinator.self) private var presentation
    @Environment(\.scenePhase) private var scenePhase
    @State private var tapCount = 0
    @State private var atmosphereDebug = AtmosphereDebugState()
    @State private var snapshotCache = AtmosphereSnapshotCache()
    @State private var manualRefreshInFlight = false
    @State private var showRefreshIndicator = false
    @State private var spinnerShownAt: Date?

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
        // Cards share the sky's hue instead of a fixed dark material (same
        // snapshot the sim renders; twilight before any data).
        let atmosphere = weather.forecast.hourly != nil
            ? snapshotCache.snapshot(from: weather, at: location.coordinates)
            : .twilight
        let cardFill = AtmosphereSampler.cardFill(snapshot: atmosphere)

        ZStack {
            WeatherSimulationView(isCoveredBySheet: presentation.sheet != nil || presentation.selectedTab != .forecast)
                .ignoresSafeArea()
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
                        HeadView()
                            .padding(.top, 35)
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
                            .accessibilityIdentifier("now.hourly")
                        DailyView()
                        AQIView()
                        ClimateView()
                            .padding(.bottom, 20)
                        Button {
                            UIApplication.shared.playHapticFeedback()
                            presentation.present(.settings)
                        } label: {
                            Label("Einstellungen", systemImage: "gearshape")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("now.settings")
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)
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
                    .padding(.bottom, 12)
            }
        }
        .environment(atmosphereDebug)
        .environment(\.cardTint, cardFill)
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: atmosphere))
        // Lighter frost than the default: thinMaterial's dark base swallowed
        // the sky; ultraThin lets the sim's color reach the cards.
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial))
        .ignoresSafeArea(edges: .top)
        .task {
            // Testing hook: `-autoPresentMapLibreAfter <seconds>` switches to the map
            // tab AFTER the NowView exists — reproduces the tap-to-open flow headless,
            // unlike -autoPresentMap which starts on the map tab at launch.
            let mapLibreDelay = UserDefaults.standard.double(forKey: "autoPresentMapLibreAfter")
            guard mapLibreDelay > 0 else { return }
            try? await Task.sleep(for: .seconds(mapLibreDelay))
            presentation.selectedTab = .maps
        }
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
    private func openRadarMap() {
        settingsService.activeTileLayer = nil
        settingsService.oscarRadarLayer = true
        UIApplication.shared.playHapticFeedback()
        presentation.selectedTab = .maps
    }
}
