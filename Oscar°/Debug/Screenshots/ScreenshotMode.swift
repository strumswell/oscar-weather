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
    static let scene: ScreenshotScene? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "screenshotScene").flatMap(ScreenshotScene.init)
        #else
        return nil
        #endif
    }()

    static var active: Bool { scene != nil }

    #if !os(watchOS)
    static var onboardingStep: OnboardingStep? {
        #if DEBUG
        guard active else { return nil }
        return UserDefaults.standard.string(forKey: "onboardingStep").flatMap(OnboardingStep.init)
        #else
        return nil
        #endif
    }
    #endif

    @MainActor
    static func bootstrap() -> Bool {
        #if DEBUG
        guard let scene else { return false }
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
    @MainActor
    private static func seedPlaces(for scene: ScreenshotScene) {
        let cityService = CityService.shared
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
        if scene == .places { cityService.disableAllCities() }
    }

    @MainActor
    private static func seedSettings(for scene: ScreenshotScene) {
        let settings = SettingService.shared
        settings.forecastModelPreference = scene == .settingsForecast ? .dwdICON : .bestMatch
        settings.dailyForecastDaytimeTemperaturesEnabled = scene == .settingsForecast
        if scene == .settingsNotifications {
            NotificationSettingsManager.shared.stageForScreenshots()
        }
    }

    @MainActor
    static func stageOnAppear() async {
        guard let scene else { return }
        await RainRadarLiveActivityManager.shared.endAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        switch scene {
        case .lockLiveActivity:
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
    var isSettings: Bool {
        self == .settingsNotifications || self == .settingsForecast
    }
}
