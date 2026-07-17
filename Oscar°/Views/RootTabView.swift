//
//  RootTabView.swift
//  Oscar°
//
//  App root: Vorhersage / Karten tabs plus the system search tab hosting the
//  locations list (the pill morphs into its search field). Einstellungen is no
//  tab — it opens as a sheet from the bottom of the forecast scroll. Also owns
//  the app-wide refresh triggers and the sheet presentation shared by all tabs.
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
        ZStack(alignment: .top) {
            TabView(selection: $presentation.selectedTab) {
                Tab("Vorhersage", systemImage: "cloud.sun", value: AppTab.forecast) {
                    NowView()
                }
                Tab("Karten", systemImage: "globe.europe.africa", value: AppTab.maps) {
                    WeatherMapDetailView(settingsService: settingsService)
                        .tint(.accentColor)
                }
                Tab(value: AppTab.search, role: .search) {
                    LocationsView()
                        .tint(.accentColor)
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            // Monochrome bar like Apple Weather's bottom controls — the accent
            // tint on the selected item is unreadable on glass over a bright
            // sky. Tint cascades into tab content, so the tabs above restore
            // the accent for their own controls (NowView stays monochrome).
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
        .environment(presentation)
        .sheet(item: $presentation.sheet, content: NowSheetView.init)
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

#Preview {
    RootTabView()
        .environment(Weather())
        .environment(Location())
        .preferredColorScheme(.dark)
}
