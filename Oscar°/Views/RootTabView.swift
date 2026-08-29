//
//  RootTabView.swift
//  Oscar°
//
//  App root: Orte / Wetter / Karten tabs. Orte is a plain tab, not the
//  system search role — the separated search pill is a button affordance
//  (instant keyboard + round trip), wrong for a dwell space like the
//  locations list; its search field lives inside the list instead.
//  Einstellungen is no tab — it opens as a sheet from the bottom of the
//  forecast scroll. Also owns the app-wide refresh triggers and the sheet
//  presentation shared by all tabs.
//

import SwiftUI
import WidgetKit

struct RootTabView: View {
    private let settingsService = SettingService.shared
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @State private var presentation = NowPresentationCoordinator()
    @State private var modelFallbackToast: String?

    var body: some View {
        @Bindable var presentation = presentation
        // The setter fires on re-taps of the current tab too — a second Orte
        // tap opens its search.
        let selection = Binding(
            get: { presentation.selectedTab },
            set: { tab in
                if tab == .places, presentation.selectedTab == .places {
                    presentation.placesSearchRequests += 1
                }
                presentation.selectedTab = tab
            }
        )
        ZStack(alignment: .top) {
            TabView(selection: selection) {
                Tab("Orte", systemImage: "location.fill", value: AppTab.places) {
                    LocationsView()
                        .tint(.primary)
                        .tabEntrance(.places)
                }
                Tab("Wetter", systemImage: "cloud.sun", value: AppTab.forecast) {
                    NowView()
                        .tabEntrance(.forecast)
                }
                Tab("Karten", systemImage: "globe.europe.africa", value: AppTab.maps) {
                    WeatherMapDetailView(settingsService: settingsService)
                        .tint(.primary)
                        .tabEntrance(.maps)
                }
            }
            // On Karten the bar stays full-size: map pans read as scroll-downs
            // and would collapse it mid-interaction.
            .tabBarMinimizeBehavior(presentation.selectedTab == .maps ? .never : .onScrollDown)
            // Monochrome bar like Apple Weather's bottom controls — the accent
            // tint on the selected item is unreadable on glass over a bright
            // sky. Tint cascades into tab content, so the tabs above swap in a
            // label tint for their own controls — the app has no color accent
            // (the AccentColor asset is empty, so .accentColor would mean
            // system blue). NowView stays monochrome.
            .tint(.white)

            if let message = modelFallbackToast, presentation.sheet == nil {
                ToastBanner(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        // Start the dismiss timer only once the toast is actually on screen
                        // (e.g. after the settings sheet that triggered the change is closed).
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.easeInOut(duration: 0.3)) { modelFallbackToast = nil }
                    }
            }
        }
        .sheet(item: $presentation.sheet, content: NowSheetView.init)
        // Outermost so the presented sheet content inherits it too — an
        // environment set inside a .sheet modifier does not reach its
        // presented content.
        .environment(presentation)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshWeatherData(isForeground: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherRefreshNeeded, object: nil)) { _ in
            refreshWeatherData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forecastModelFallback)) { _ in
            withAnimation(.spring(duration: 0.4)) {
                modelFallbackToast = String(localized: "Außerhalb des Modells – Automatik aktiv.")
            }
        }
    }

    /// The single refresh path for every weather-data input change (foreground return,
    /// GPS move, city switch, unit/format/model change). The individual steps are cheap
    /// or self-guarded, so running all of them on every trigger beats five near-identical
    /// handlers that each forget a different step.
    private func refreshWeatherData(isForeground: Bool = false) {
        // Clear any stale fallback notice; the refresh re-posts one if it still applies.
        modelFallbackToast = nil
        Task {
            await weather.refresh(location: location)
            await NotificationSettingsManager.shared.syncLocationUpdate()
            await WidgetBasemapRenderer.refreshIfNeeded()
            if isForeground {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}

/// One-shot reveal when a tab becomes selected: a quick fade with a subtle
/// settle-in scale. Runs as a phase cycle (hide near-instantly, then animate
/// in) so the trigger and the reveal can't coalesce into one no-op frame;
/// re-taps of the current tab don't replay it. Under Reduce Motion the scale
/// is dropped and only the crossfade remains.
private struct TabEntranceEffect: ViewModifier {
    let tab: AppTab
    @Environment(NowPresentationCoordinator.self) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entrances = 0

    func body(content: Content) -> some View {
        content
            .phaseAnimator([true, false], trigger: entrances) { view, shown in
                view
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.98)
            } animation: { shown in
                shown ? .smooth(duration: 0.28) : .linear(duration: 0.01)
            }
            // initial: true covers a tab that mounts already selected (launch,
            // first visit of a lazily created tab) — onChange alone would miss
            // those because the selection changed before the view existed.
            .onChange(of: presentation.selectedTab == tab, initial: true) { _, isSelected in
                if isSelected {
                    entrances += 1
                }
            }
    }
}

private extension View {
    func tabEntrance(_ tab: AppTab) -> some View {
        modifier(TabEntranceEffect(tab: tab))
    }
}

#Preview {
    RootTabView()
        .environment(Weather())
        .environment(Location())
        .preferredColorScheme(.dark)
}
