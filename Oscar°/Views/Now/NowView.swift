//
//  NowView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI

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
    private var stageSize: CGSize? { presentation.forecastSize }

    private static let scrollTopPadding: CGFloat = 40
    private static let firstPageOvershoot: CGFloat = 48

    private var spinnerPending: Bool {
        weather.isLoading && weather.hasContent && !manualRefreshInFlight && scenePhase == .active
    }

    private var arrangement: SectionArrangement {
        settingsService.arrangement(for: LayoutForm.of(stageSize ?? .zero))
    }

    private var sections: [NowSection] {
        isTwoColumn ? stageSections + feedSections : arrangement.pageSections
    }

    private var firstPageCount: Int { sections.first == .radar ? 2 : 1 }

    private var isTwoColumn: Bool { presentation.forecastIsWide }

    private var stageSections: [NowSection] { arrangement.stageSections }

    private var feedSections: [NowSection] { arrangement.feedSections }

    var body: some View {
        let atmosphere = weather.forecast.hourly != nil
            ? snapshotCache.snapshot(from: weather, at: location.coordinates)
            : .twilight
        let cardFill = AtmosphereSampler.cardFill(snapshot: atmosphere)

        ZStack {
            WeatherSimulationView(isOffTab: presentation.selectedTab != .forecast)
                .ignoresSafeArea()
            if weather.hasContent {
                Group {
                    if isTwoColumn {
                        HStack(spacing: 0) {
                            forecastScroll { stage }
                                .scrollBounceBehavior(.basedOnSize)
                                .frame(maxWidth: WideForecast.maxColumnWidth)
                            forecastScroll { feed }
                                .frame(maxWidth: WideForecast.maxColumnWidth)
                        }
                    } else {
                        forecastScroll { page }
                            .padding(.top, Self.scrollTopPadding)
                    }
                }
                .task(id: spinnerPending) {
                    guard spinnerPending else {
                        if showRefreshIndicator, let shownAt = spinnerShownAt {
                            let remaining = 0.6 - Date.now.timeIntervalSince(shownAt)
                            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                        }
                        showRefreshIndicator = false
                        spinnerShownAt = nil
                        return
                    }
                    guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
                    guard !Task.isCancelled else { return }
                    spinnerShownAt = .now
                    showRefreshIndicator = true
                }
            } else if weather.loadState == .failed {
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
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
        .ignoresSafeArea(edges: isTwoColumn ? [] : .top)
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { CatModel.shared.dismissMenu(outside: $0.location) })
        .overlay { SupportNudgeOverlay(isEnabled: weather.hasContent) }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
            if let old = stageSize, old.width == size.width, abs(old.height - size.height) < 100 {
                return
            }
            presentation.forecastSize = size
            LayoutFrame.rememberWideWindow(size)
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                refreshIndicator
                HeadView()
                    .padding(.top, 35)
                    .debugConsoleTap(countDebugTap)
                    .headCat()
                sectionList(sections.prefix(firstPageCount))
            }
            .frame(minHeight: firstPageMinHeight, alignment: .topLeading)
            sectionList(sections.dropFirst(firstPageCount))
            pageEnd
        }
        .animation(.easeInOut(duration: 0.3), value: showRefreshIndicator)
        .animation(.snappy, value: sections)
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeadView(compact: true)
                .fixedSize(horizontal: false, vertical: true)
                .debugConsoleTap(countDebugTap)
                .headCat()
            sectionList(stageSections[...])
        }
        .padding(.bottom)
        .frame(minHeight: stageSize?.height, alignment: .top)
        .animation(.snappy, value: stageSections)
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 0) {
            refreshIndicator
            sectionList(feedSections[...], isWide: true)
            pageEnd
        }
        .animation(.easeInOut(duration: 0.3), value: showRefreshIndicator)
        .animation(.snappy, value: feedSections)
    }

    @ViewBuilder
    private var refreshIndicator: some View {
        if showRefreshIndicator {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(uiColor: .label))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var pageEnd: some View {
        if sections.isEmpty {
            Button("Abschnitte hinzufügen", systemImage: "plus") {
                Haptics.impact()
                presentation.present(.layout)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
        }
        footer
            .padding(.top, 28)
        if weather.debug {
            VStack {
                DebugPermissionControls()
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

    private func forecastScroll(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.vertical) {
            content()
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { old, new in
            let delta = abs(new - old)
            if delta < 1500 { UsageStatsStore.shared.addScroll(points: delta) }
        }
        .refreshable {
            manualRefreshInFlight = true
            await Task { await weather.refresh(location: location) }.value
            manualRefreshInFlight = false
        }
    }

    private func sectionList(_ sections: ArraySlice<NowSection>, isWide: Bool = false) -> some View {
        ForEach(sections) { section in
            section.view(openRadarMap: openRadarMap, isWide: isWide)
                .fixedSize(horizontal: false, vertical: section != .map)
                .padding(.top, 28)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                ProviderLogo(asset: "logo-dwd", height: 36)
                ProviderLogo(asset: "logo-open-meteo", height: 32)
                ProviderLogo(asset: "logo-oscar-server", height: 28)
            }
            .foregroundStyle(.white)
            .opacity(0.7)
            .shadow(color: .black.opacity(0.35), radius: 1)
            .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
            .padding(12)
            .drawingGroup()
            .padding(-12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "DWD, Open-Meteo & Oscar Server"))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            Button {
                Haptics.impact()
                presentation.present(.settings)
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .opacity(0.7)
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("now.settings")
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }

    private var firstPageMinHeight: CGFloat? {
        (stageSize?.height).map { $0 - Self.scrollTopPadding + Self.firstPageOvershoot }
    }
}

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
    private func countDebugTap() {
        tapCount += 1
        guard tapCount == 10 else { return }
        tapCount = 0
        weather.debug.toggle()
        Haptics.impact()
    }

    private func openRadarMap() {
        settingsService.activeTileLayer = nil
        settingsService.oscarRadarLayer = true
        Haptics.impact()
        presentation.selectedTab = .maps
    }
}

private extension View {
    func debugConsoleTap(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(TapGesture().onEnded(action))
    }
}
