//
//  ScreenshotTests.swift
//  Oscar°UITests
//
//  App Store screenshot run for fastlane snapshot: every test launches the app
//  into a `-screenshotScene`, navigates through the real UI, and captures one
//  numbered screenshot per scene. Deterministic data comes from the in-app
//  fixture server (ScreenshotFixtureServer); only the map scenes and the radar
//  widget composite show live radar.
//
//  snapshot() is always called with `timeWaitingForIdle: 0`: SnapshotHelper's
//  default idle wait polls for a status-bar network spinner that no longer
//  exists on modern iOS, so it burns its full 20 s timeout on every capture.
//  Each scene already waits explicitly for its content instead.
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func skipOnPad() throws {
        try XCTSkipIf(isPad, "iPhone-only scene")
    }

    private func swipeUp(_ app: XCUIApplication) {
        guard isPad else { return app.swipeUp(velocity: .fast) }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func launch(scene: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [
            "-screenshotScene", scene,
            "-hasCompletedOnboarding", scene == "onboarding" ? "NO" : "YES",
        ]
        app.launchArguments += extraArguments
        if isPad && !extraArguments.contains("-oscarRadarLayer") {
            app.launchArguments += ["-oscarRadarLayer", "YES"]
        }
        app.launch()
        return app
    }

    @discardableResult
    private func openSettings(_ app: XCUIApplication) -> XCUIElement {
        waitForNowContent(app)
        let entry = app.descendants(matching: .any)["now.settings"].firstMatch
        for _ in 0..<14 {
            app.swipeUp(velocity: .fast)
            usleep(350_000)
        }
        XCTAssertTrue(entry.exists, "Settings entry never reached the bottom of the scroll")
        tapFrameCenter(entry, in: app)
        let card = app.descendants(matching: .any)["settings.memberCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Settings sheet never opened")
        return card
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if isSufficientlyVisible(element, in: app) { return true }
            swipeUp(app)
            usleep(400_000)
        }
        let visible = isSufficientlyVisible(element, in: app)
        XCTAssertTrue(visible, "Could not scroll to \(element)")
        return visible
    }

    private func safeArea(of app: XCUIApplication) -> CGRect {
        app.windows.firstMatch.frame.insetBy(dx: 0, dy: 120)
    }

    private func isSufficientlyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let visible = frame.intersection(safeArea(of: app))
        guard !visible.isNull, !visible.isEmpty else { return false }
        return visible.height >= min(frame.height * 0.9, 120)
            && visible.width >= min(frame.width * 0.9, 120)
    }

    private func tapFrameCenter(_ element: XCUIElement, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: element.frame.midX, dy: element.frame.midY))
            .tap()
    }

    private func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        let visible = element.frame.intersection(safeArea(of: app))
        let point = visible.isNull || visible.isEmpty
            ? CGPoint(x: element.frame.midX, y: element.frame.midY)
            : CGPoint(x: visible.midX, y: visible.midY)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    private func waitForNowContent(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["now.daily"].waitForExistence(timeout: 30),
            "Now screen never showed content"
        )
    }

    // MARK: - Scenes

    func test01NowRain() {
        let app = launch(scene: "nowRain")
        waitForNowContent(app)
        sleep(4)
        snapshot("01_now_rain", timeWaitingForIdle: 0)
    }

    func test02Forecast() {
        let app = launch(scene: "nowForecast", extraArguments: isPad ? [
            "-oscarRadarLayer", "NO",
            "-cloudLayerActive", "YES",
        ] : [])
        waitForNowContent(app)
        let hourly = app.descendants(matching: .any)["now.hourly"].firstMatch
        scrollTo(hourly, in: app)
        let targetY: CGFloat = 150
        let delta = hourly.frame.minY - targetY
        if delta > 1 {
            let window = app.windows.firstMatch.frame
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to = app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5, dy: 0.75 - delta / window.height))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        sleep(3)
        snapshot("02_forecast", timeWaitingForIdle: 0)
    }

    func test03MapRadar() {
        let app = launch(scene: "mapRadar", extraArguments: [
            "-autoPresentMap", "YES",
            "-oscarRadarLayer", "YES",
            "-mapInitialZoom", "6.5",
        ])
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(7)
        snapshot("03_map_radar", timeWaitingForIdle: 0)
    }

    func test04MapTemp() {
        let app = launch(scene: "mapTemp", extraArguments: [
            "-autoPresentMap", "YES",
            "-oscarRadarLayer", "NO",
            "-activeTileLayer", "icon_temp",
            "-showIsobars", "YES",
            "-mapInitialZoom", "6",
        ])
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(7)
        snapshot("04_map_temp", timeWaitingForIdle: 0)
    }

    func test04bMapWind() throws {
        try skipOnPad()
        let app = launch(scene: "mapWind", extraArguments: [
            "-autoPresentMap", "YES",
            "-oscarRadarLayer", "NO",
            "-activeTileLayer", "icon_wind",
            "-mapInitialZoom", "6",
        ])
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(7)
        snapshot("90_map_wind", timeWaitingForIdle: 0)
    }

    func test04cMapPressure() throws {
        try skipOnPad()
        let app = launch(scene: "mapPressure", extraArguments: [
            "-autoPresentMap", "YES",
            "-oscarRadarLayer", "NO",
            "-activeTileLayer", "icon_pressure",
            "-mapInitialZoom", "6",
        ])
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(7)
        snapshot("91_map_pressure", timeWaitingForIdle: 0)
    }

    func test05Ensemble() {
        let app = launch(scene: "ensemble")
        waitForNowContent(app)
        let daily = app.descendants(matching: .any)["now.daily"].firstMatch
        scrollTo(daily, in: app)
        tapVisible(app.buttons["now.daily"].firstMatch, in: app)
        let ensemble = app.buttons["hourly.ensemble"].firstMatch
        _ = ensemble.waitForExistence(timeout: 10)
        ensemble.tap()
        sleep(5)
        snapshot("05_ensemble", timeWaitingForIdle: 0)
    }

    func test06AirQuality() {
        let app = launch(scene: "airQuality")
        waitForNowContent(app)
        let anyGauge = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'now.environment.'"))
            .firstMatch
        scrollTo(anyGauge, in: app, maxSwipes: 8)
        let aqiGauge = app.descendants(matching: .any)["now.environment.aqi"].firstMatch
        var stripSwipes = 0
        while !isSufficientlyVisible(aqiGauge, in: app) && stripSwipes < 6 {
            let window = app.windows.firstMatch.frame
            let rowY = anyGauge.frame.midY / window.height
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: rowY))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: rowY)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            stripSwipes += 1
        }
        XCTAssertTrue(isSufficientlyVisible(aqiGauge, in: app), "AQI gauge never entered the viewport")
        tapVisible(aqiGauge, in: app)
        sleep(4)
        snapshot("06_air_quality", timeWaitingForIdle: 0)
    }

    func test07Klima() {
        let app = launch(scene: "climate")
        waitForNowContent(app)
        let climateCard = app.descendants(matching: .any)["now.climate"].firstMatch
        _ = climateCard.waitForExistence(timeout: 10)
        scrollTo(climateCard, in: app, maxSwipes: 12)
        tapVisible(climateCard, in: app)
        sleep(3)
        snapshot("07_klima", timeWaitingForIdle: 0)
    }

    func test08NowClear() throws {
        try skipOnPad()
        let app = launch(scene: "nowClear")
        waitForNowContent(app)
        sleep(4)
        snapshot("08_now_clear", timeWaitingForIdle: 0)
    }

    func test09Widgets() throws {
        try skipOnPad()
        let app = launch(scene: "widgets")
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot.widgetGallery.ready"].waitForExistence(timeout: 30)
        )
        snapshot("09_widgets", timeWaitingForIdle: 0)
    }

    // MARK: - Library scenes

    func test20HourlyDetail() {
        let app = launch(scene: "hourlyDetail")
        waitForNowContent(app)
        let header = app.descendants(matching: .any)["now.hourly"].firstMatch
        scrollTo(header, in: app)
        let x = isPad ? header.frame.midX : app.windows.firstMatch.frame.midX
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x, dy: header.frame.maxY + 80))
            .tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["hourly.detail"].waitForExistence(timeout: 10),
            "Hourly detail sheet never opened"
        )
        sleep(4)
        snapshot("20_hourly_detail", timeWaitingForIdle: 0)
    }

    func test21MapLayers() {
        let app = launch(scene: "mapLayers", extraArguments: [
            "-autoPresentMap", "YES",
            "-oscarRadarLayer", "YES",
            "-mapInitialZoom", "6.5",
        ])
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(6)
        app.descendants(matching: .any)["map.layerPicker"].firstMatch.tap()
        sleep(3)
        snapshot("21_map_layers", timeWaitingForIdle: 0)
        guard !isPad else { return }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.52))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.05)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
        let display = app.descendants(matching: .any)["map.layers.display"].firstMatch
        for _ in 0..<10 where !isSufficientlyVisible(display, in: app) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.8))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.35)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            usleep(400_000)
        }
        XCTAssertTrue(isSufficientlyVisible(display, in: app), "Display toggles never scrolled into view")
        let startY = display.frame.minY
        let targetY: CGFloat = 190
        if startY > targetY {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 13, dy: startY + 40))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: 13, dy: targetY + 40)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        sleep(2)
        snapshot("22_map_layer_settings", timeWaitingForIdle: 0)
    }

    func test23AlertDetail() throws {
        try skipOnPad()
        let app = launch(scene: "nowRain")
        waitForNowContent(app)
        let badge = app.descendants(matching: .any)["now.alert"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "Alert badge never appeared")
        tapVisible(badge, in: app)
        sleep(3)
        snapshot("23_alert_detail", timeWaitingForIdle: 0)
    }

    func test24Settings() throws {
        try skipOnPad()
        let app = launch(scene: "customization")
        openSettings(app)
        sleep(2)
        snapshot("24_settings", timeWaitingForIdle: 0)
    }

    func test25SettingsNotifications() throws {
        try skipOnPad()
        let app = launch(scene: "settingsNotifications")
        openSettings(app)
        let alerts = app.descendants(matching: .any)["settings.alerts"].firstMatch
        XCTAssertTrue(alerts.waitForExistence(timeout: 10))
        tapVisible(alerts, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["notifications.rainAlerts"].waitForExistence(timeout: 10)
        )
        sleep(2)
        snapshot("25_settings_notifications", timeWaitingForIdle: 0)
    }

    func test26SettingsForecast() throws {
        try skipOnPad()
        let app = launch(scene: "settingsForecast")
        openSettings(app)
        let entry = app.descendants(matching: .any)["settings.forecast"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        tapVisible(entry, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["forecast.daytimeTemperatures"]
                .waitForExistence(timeout: 10)
        )
        sleep(2)
        snapshot("26_settings_forecast", timeWaitingForIdle: 0)
    }

    func test27MemberCardDock() throws {
        try skipOnPad()
        let app = launch(scene: "customization")
        let card = openSettings(app)
        tapVisible(card, in: app)
        sleep(3)
        snapshot("27_member_card_dock", timeWaitingForIdle: 0)
    }

    func test28Onboarding() throws {
        try skipOnPad()
        let steps = [
            ("welcome", "28_onboarding_welcome"),
            ("features", "29_onboarding_features"),
            ("location", "30_onboarding_location"),
            ("notifications", "32_onboarding_notifications"),
            ("crashReports", "32b_onboarding_crash_reports"),
            ("finale", "33_onboarding_finale"),
        ]
        for (step, name) in steps {
            let app = launch(scene: "onboarding", extraArguments: ["-onboardingStep", step])
            _ = app.wait(for: .runningForeground, timeout: 30)
            sleep(5)
            snapshot(name, timeWaitingForIdle: 0)
            app.terminate()
        }

        let app = launch(scene: "onboarding", extraArguments: ["-onboardingStep", "manualLocation"])
        _ = app.wait(for: .runningForeground, timeout: 30)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "Search field never appeared")
        field.tap()
        field.typeText("Le")
        let hit = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Leipzig")
        ).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 15), "Geocoder fixtures never rendered")
        sleep(2)
        snapshot("31_onboarding_city", timeWaitingForIdle: 0)
    }

    func test34Places() throws {
        try skipOnPad()
        let app = launch(scene: "places")
        waitForNowContent(app)
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.staticTexts["Essen"].waitForExistence(timeout: 30), "Orte list stayed empty"
        )
        sleep(5)
        snapshot("34_places", timeWaitingForIdle: 0)
    }

    // MARK: - Lock screen

    func test80LockNotifications() throws {
        try skipOnPad()
        let app = launch(scene: "lockNotifications")
        _ = app.wait(for: .runningForeground, timeout: 30)
        allowNotificationsIfAsked()
        pressLockButton()
        sleep(22)
        pressLockButton()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80)).tap()
        sleep(3)
        snapshot("37_lock_notifications", timeWaitingForIdle: 0)
        unlock()
    }

    func test81LockLiveActivity() throws {
        try skipOnPad()
        let app = launch(scene: "lockLiveActivity")
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(6)
        pressLockButton()
        sleep(6)
        pressLockButton()
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.71, dy: 0.81)).tap()
        sleep(4)
        snapshot("38_lock_live_activity", timeWaitingForIdle: 0)
        unlock()
    }

    // MARK: - Lock screen helpers

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN {'Allow', 'Erlauben', 'İzin Ver'}")
        ).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }
    }

    private func pressLockButton() {
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else {
            XCTFail("pressLockButton is gone — the lock screen scenes need a new door")
            return
        }
        _ = XCUIDevice.shared.perform(selector)
        sleep(3)
    }

    private func unlock() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.985))
            .press(
                forDuration: 0.1,
                thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            )
        sleep(2)
    }
}
