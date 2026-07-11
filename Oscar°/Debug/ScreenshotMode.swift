//
//  ScreenshotMode.swift
//  Oscar°
//
//  App Store screenshot staging (fastlane snapshot). The UI tests launch the
//  app with `-screenshotScene <rawValue>`; the bootstrap swaps the network
//  layer for ScreenshotFixtureServer so every prod code path runs unmodified
//  against deterministic data. Navigation happens through the real UI (the
//  tests tap), not through injected presentation state.
//

import Foundation

enum ScreenshotScene: String {
    case nowRain
    case nowForecast
    case mapRadar
    case mapTemp
    case mapWind
    case mapPressure
    case ensemble
    case airQuality
    case climate
    case customization
    case widgets
    case notifications
}

enum ScreenshotMode {
    /// `-screenshotScene <name>` lands in the UserDefaults argument domain.
    static let scene: ScreenshotScene? = UserDefaults.standard
        .string(forKey: "screenshotScene")
        .flatMap(ScreenshotScene.init)

    static var active: Bool { scene != nil }

    /// Installs the fixture server and seeds state that can't be expressed as
    /// launch-argument defaults. Returns whether a screenshot scene is active
    /// so the caller can skip crash reporting for staged runs. Also compiled
    /// into the watch target, which has no CityService — the watch app pins
    /// its Location object itself.
    @MainActor
    static func bootstrap() -> Bool {
        guard let scene else { return false }
        _ = scene
        // Three interception layers, one route table: URLProtocol catches the
        // plain URLSession consumers (radar grids/tiles, alerts) on iOS; the
        // middleware + fetch seam cover the OpenAPI clients and fetchWithRetry
        // everywhere — on watchOS URLSession loads out of process and the
        // URLProtocol never fires.
        URLProtocol.registerClass(ScreenshotFixtureServer.self)
        APIClient.stagingMiddlewares = [ScreenshotFixtureMiddleware()]
        APIClient.stagedFetch = { ScreenshotFixtureServer.stagedFetch($0) }
        #if !os(watchOS)
        // A selected city pins the location name and coordinates without any
        // GPS or reverse-geocoding dependency on the freshly wiped simulator.
        if CityService.shared.getSelectedCity() == nil {
            CityService.shared.addCity(searchResult: .init(
                name: "Leipzig",
                latitude: Float(ScreenshotFixtures.latitude),
                longitude: Float(ScreenshotFixtures.longitude)
            ))
        }
        if scene == .customization {
            MemberCardStickerStore().save(ScreenshotFixtures.stickerPlacements)
        }
        #endif
        return true
    }
}
