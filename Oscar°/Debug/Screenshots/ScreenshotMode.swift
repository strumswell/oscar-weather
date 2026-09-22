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

import CoreLocation
import SwiftUI
import Foundation
import UserNotifications

enum ScreenshotScene: String {
    case nowRain
    case nowClear
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
    case hourlyDetail
    case mapLayers
    case places
    case settingsNotifications
    case settingsForecast
    case onboarding
    case lockNotifications
    case lockLiveActivity
}

enum ScreenshotMode {
    /// `-screenshotScene <name>` lands in the UserDefaults argument domain.
    static let scene: ScreenshotScene? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "screenshotScene").flatMap(ScreenshotScene.init)
        #else
        return nil
        #endif
    }()

    static var active: Bool { scene != nil }

    #if !os(watchOS)
    /// `-onboardingStep <rawValue>` drops the flow straight onto one screen, so
    /// every step gets a capture without tapping through permission prompts.
    /// (The watch has no onboarding flow, hence no OnboardingStep type.)
    static var onboardingStep: OnboardingStep? {
        #if DEBUG
        guard active else { return nil }
        return UserDefaults.standard.string(forKey: "onboardingStep").flatMap(OnboardingStep.init)
        #else
        return nil
        #endif
    }
    #endif

    /// Installs the fixture server and seeds state that can't be expressed as
    /// launch-argument defaults. Returns whether a screenshot scene is active
    /// so the caller can skip crash reporting for staged runs. Also compiled
    /// into the watch target, which has no CityService — the watch app pins
    /// its Location object itself.
    @MainActor
    static func bootstrap() -> Bool {
        #if DEBUG
        guard let scene else { return false }
        // Three interception layers, one route table: URLProtocol catches the
        // plain URLSession consumers (radar grids/tiles, alerts) on iOS; the
        // middleware + fetch seam cover the OpenAPI clients and fetchWithRetry
        // everywhere — on watchOS URLSession loads out of process and the
        // URLProtocol never fires.
        URLProtocol.registerClass(ScreenshotFixtureServer.self)
        APIClient.stagingMiddlewares = [ScreenshotFixtureMiddleware()]
        APIClient.stagedFetch = { ScreenshotFixtureServer.stagedFetch($0) }
        #if !os(watchOS)
        seedPlaces(for: scene)
        seedSettings(for: scene)
        if scene == .customization || scene.isSettings {
            MemberCardStickerStore().save(ScreenshotFixtures.stickerPlacements)
        }
        #else
        // No CityService on the watch: the GPS coordinate IS its place, and the
        // first refresh relabels the app's pinned name by reverse-geocoding it.
        // Left on the placeholder, every watch capture reads "Berlin".
        LocationService.shared.gpsLocation = CLLocationCoordinate2D(
            latitude: ScreenshotFixtures.latitude,
            longitude: ScreenshotFixtures.longitude
        )
        #endif
        return true
        #else
        return false
        #endif
    }

    #if DEBUG && !os(watchOS)
    /// Saved places, rebuilt from scratch: the reinstall happens once per
    /// language pass, so every scene in that pass shares one install and
    /// appending would let one scene's cities leak into the next capture.
    @MainActor
    private static func seedPlaces(for scene: ScreenshotScene) {
        let cityService = CityService.shared
        // A pinned GPS coordinate keeps the "Mein Standort" card off whatever
        // fix the last run cached. Berlin, so it isn't a second Leipzig.
        LocationService.shared.gpsLocation = ScreenshotFixtures.gpsCoordinate
        if scene == .places {
            LocationService.shared.authStatus = .authorizedWhenInUse
        }
        if !cityService.cities.isEmpty {
            cityService.deleteCity(offsets: IndexSet(integersIn: cityService.cities.indices))
        }
        for place in ScreenshotFixtures.savedPlaces(for: scene) {
            cityService.addCity(name: place.name, latitude: place.latitude, longitude: place.longitude)
        }
        // The Orte list shows the GPS row as the selected one.
        if scene == .places { cityService.disableAllCities() }
    }

    /// Preference-backed settings the settings scenes show switched on. Set on
    /// the service (not as launch arguments): these live in the app-group
    /// defaults, which the argument domain never reaches.
    @MainActor
    private static func seedSettings(for scene: ScreenshotScene) {
        let settings = SettingService.shared
        settings.forecastModelPreference = scene == .settingsForecast ? .dwdICON : .bestMatch
        settings.dailyForecastDaytimeTemperaturesEnabled = scene == .settingsForecast
        settings.hourlyDetailShowsChapters = false
        if scene == .settingsNotifications {
            NotificationSettingsManager.shared.stageForScreenshots()
        }
    }

    /// Staging that needs a foregrounded app: ActivityKit rejects a request
    /// made from `init`, and a notification request needs a live scene for its
    /// permission prompt. Called from the app's first `.task`.
    @MainActor
    static func stageOnAppear() async {
        guard let scene else { return }
        // A card left behind by a killed or failed run must go first: see
        // scenePhaseDidChange for what a live one does to every later launch.
        // Delivered notifications too: they stay on the lock screen and would
        // push the Live Activity card up, off the coordinates its test taps.
        await RainRadarLiveActivityManager.shared.endAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        switch scene {
        case .lockLiveActivity:
            // `-screenshotLiveActivityPhase` is Social Studio's; the pipeline shows rain.
            let phase = UserDefaults.standard.string(forKey: "screenshotLiveActivityPhase")
                .flatMap(RainRadarActivityAttributes.ContentState.Phase.init) ?? .raining
            try? RainRadarLiveActivityManager.shared.startPreview(phase: phase)
        case .lockNotifications:
            await ScreenshotLockScreenNotifications.schedule()
        default:
            break
        }
    }

    @MainActor private static var wasBackgrounded = false

    /// The lock-screen card must not outlive its capture: while an activity is
    /// alive, liveactivitiesd relaunches the app WITHOUT launch arguments
    /// whenever its process dies (and again on every simulator boot), and that
    /// argument-less instance — real network, onboarding, no fixtures — races
    /// the next test's own launch. The lock backgrounds the app and the test's
    /// unlock after the shot brings it back, so the card ends on that return.
    @MainActor
    static func scenePhaseDidChange(_ phase: ScenePhase) {
        guard scene == .lockLiveActivity else { return }
        if phase == .background { wasBackgrounded = true }
        guard phase == .active, wasBackgrounded else { return }
        Task { await RainRadarLiveActivityManager.shared.endAll() }
    }
    #endif
}

extension ScreenshotScene {
    /// Scenes that open the settings sheet; they all show the stickered card.
    var isSettings: Bool {
        self == .settingsNotifications || self == .settingsForecast
    }
}
