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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presentation = NowPresentationCoordinator()
    @State private var modelFallbackToast: String?

    var body: some View {
        @Bindable var presentation = presentation
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
            if settingsService.classicTheme {
                ClassicWeatherView()
            } else {
                TabView(selection: selection) {
                    Tab("Orte", systemImage: "location.fill", value: AppTab.places) {
                        LocationsView()
                            .tint(.primary)
                    }
                    Tab("Wetter", systemImage: "cloud.sun", value: AppTab.forecast) {
                        NowView()
                    }
                    Tab("Karten", systemImage: "globe.europe.africa", value: AppTab.maps) {
                        WeatherMapDetailView(settingsService: settingsService)
                            .tint(.primary)
                    }
                }
                .tabBarMinimizeBehavior(horizontalSizeClass == .regular || presentation.selectedTab == .maps || presentation.isNudgeOut ? .never : .onScrollDown)
                .tint(.white)
                .layerPickerInspector(isPresented: $presentation.isLayerPickerPresented, settingsService: settingsService) {
                    presentation.selectLayer($0, $1)
                }
            }

            if let message = modelFallbackToast, presentation.sheet == nil {
                ToastBanner(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.3)) { modelFallbackToast = nil }
                    }
            }
        }
        .sheet(item: $presentation.sheet, content: NowSheetView.init)
        .onOpenURL { url in
            guard url.scheme == "oscar", url.host == "radar" else { return }
            presentation.selectedTab = .maps
        }
        .environment(presentation)
        .focusedSceneValue(presentation)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshWeatherData(isForeground: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherRefreshNeeded, object: nil)) { _ in
            refreshWeatherData()
        }
        .onChange(of: weather.lastUpdated) { _, updated in
            if updated != nil { recordUsageConditions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forecastModelFallback)) { _ in
            withAnimation(.spring(duration: 0.4)) {
                modelFallbackToast = String(localized: "Außerhalb des Modells – Automatik aktiv.")
            }
        }
    }

    private func recordUsageConditions() {
        UsageStatsStore.shared.recordConditions(
            temperature: weather.forecast.current?.temperature,
            temperatureUnit: "°C",
            wind: weather.forecast.current?.windspeed,
            windUnit: "km/h",
            precipitation: weather.forecast.current?.precipitation,
            precipitationUnit: "mm",
            uv: environmentValue(from: weather.air.hourly?.uv_index, time: weather.air.hourly?.time ?? []),
            place: location.name
        )
    }

    private func refreshWeatherData(isForeground: Bool = false) {
        withAnimation(.easeInOut(duration: 0.3)) { modelFallbackToast = nil }
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

struct OscarCommands: Commands {
    @FocusedValue(NowPresentationCoordinator.self) private var presentation

    var body: some Commands {
        CommandMenu("Wetter") {
            Group {
                Button("Orte") { presentation?.selectedTab = .places }
                    .keyboardShortcut("1")
                Button("Wetter") { presentation?.selectedTab = .forecast }
                    .keyboardShortcut("2")
                Button("Karten") { presentation?.selectedTab = .maps }
                    .keyboardShortcut("3")
                Divider()
                Button("Aktualisieren") {
                    NotificationCenter.default.post(name: .weatherRefreshNeeded, object: nil)
                }
                .keyboardShortcut("r")
            }
            .disabled(presentation == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen") { presentation?.present(.settings) }
                .keyboardShortcut(",")
                .disabled(presentation == nil)
        }
    }
}

#Preview {
    RootTabView()
        .environment(Weather())
        .environment(Location())
        .preferredColorScheme(.dark)
}
