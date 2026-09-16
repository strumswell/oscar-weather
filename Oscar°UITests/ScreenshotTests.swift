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
    }

    private func launch(scene: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [
            "-screenshotScene", scene,
            // The onboarding scenes want the flow, everything else skips it.
            "-hasCompletedOnboarding", scene == "onboarding" ? "NO" : "YES",
        ]
        app.launchArguments += extraArguments
        app.launch()
        return app
    }

    /// Opens the settings sheet from the bottom of the forecast scroll.
    /// Not via `scrollTo`/`tapVisible`: the entry is the LAST thing in the
    /// scroll and parks ~30 pt inside the 120 pt bottom band those reserve, so
    /// they can never call it visible. It lands clear of the tab bar, so a
    /// direct coordinate tap on its own frame is the reliable move.
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

    /// Vertically scrolls until the element's center is comfortably on screen.
    /// Deliberately avoids `isHittable`: while a fast swipe settles, lazy
    /// content has transient frames and the hittability query THROWS
    /// ("Activation point invalid…") instead of returning false. Frame math
    /// never throws; visible-center + coordinate taps replace hit testing.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if isSufficientlyVisible(element, in: app) { return true }
            app.swipeUp(velocity: .fast)
            usleep(400_000)  // let the scroll settle before re-reading frames
        }
        let visible = isSufficientlyVisible(element, in: app)
        XCTAssertTrue(visible, "Could not scroll to \(element)")
        return visible
    }

    /// The screen area safely below the status bar and above the home
    /// indicator, where taps land reliably.
    private func safeArea(of app: XCUIApplication) -> CGRect {
        app.windows.firstMatch.frame.insetBy(dx: 0, dy: 120)
    }

    /// Enough of the element is on screen to tap it: its intersection with
    /// the safe area is (almost) its own height, or 120 pt for elements
    /// taller than the screen (the 12-day daily card never fits whole).
    private func isSufficientlyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let visible = frame.intersection(safeArea(of: app))
        guard !visible.isNull, !visible.isEmpty else { return false }
        return visible.height >= min(frame.height * 0.9, 120)
            && visible.width >= min(frame.width * 0.9, 120)
    }

    /// Tap the element's own center, safe area be damned.
    private func tapFrameCenter(_ element: XCUIElement, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: element.frame.midX, dy: element.frame.midY))
            .tap()
    }

    /// Tap the center of the element's VISIBLE part via screen coordinates —
    /// no hittability evaluation, which throws on transient frames.
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
        let app = launch(scene: "nowForecast")
        waitForNowContent(app)
        // Composition: hourly strip near the top, the daily list filling the
        // rest. Scroll to the hourly section, then drag by the exact distance
        // that parks its top at `targetY` (slow drag + hold, so no momentum
        // overshoots the position). Not tighter than this: the conditions row
        // sits right above the section and would land under the status bar,
        // colliding with the clock.
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

    // Wind and pressure layer captures: composition sources for the combined
    // "Temperatur, Wind und Druck" App Store shot (scenes are marked hidden in
    // frame-studio/layout.json, so they get no framed export of their own).
    func test04bMapWind() {
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

    func test04cMapPressure() {
        // Isobars turn on automatically for pressure layers.
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
        tapVisible(daily, in: app)
        sleep(5)
        snapshot("05_ensemble", timeWaitingForIdle: 0)
    }

    func test06AirQuality() {
        let app = launch(scene: "airQuality")
        waitForNowContent(app)
        // The environment gauges are a HORIZONTAL strip ordered by severity,
        // so the AQI card's position depends on the launch hour (afternoon
        // ozone/pollen outrank a low AQI). Scroll the strip vertically into
        // view via its first gauge, then swipe the strip itself left until
        // the AQI card is on screen.
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
        // The card appears once the (fixture) archive is reduced; give it a
        // moment to exist, then scroll it into view.
        _ = climateCard.waitForExistence(timeout: 10)
        scrollTo(climateCard, in: app, maxSwipes: 12)
        tapVisible(climateCard, in: app)
        sleep(3)
        snapshot("07_klima", timeWaitingForIdle: 0)
    }

    /// The calm counterpart to scene 01: same hero, clear summer sky, no rain
    /// animation and no alert banner.
    func test08NowClear() {
        let app = launch(scene: "nowClear")
        waitForNowContent(app)
        sleep(4)
        snapshot("08_now_clear", timeWaitingForIdle: 0)
    }

    func test09Widgets() {
        let app = launch(scene: "widgets")
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot.widgetGallery.ready"].waitForExistence(timeout: 30)
        )
        snapshot("09_widgets", timeWaitingForIdle: 0)
    }

    // MARK: - Library scenes
    //
    // Captured for docs, store pages and release notes rather than the ten
    // App Store slots, so they are marked `hidden` (source-only) in
    // frame-studio/layout.json and get no framed export until promoted.

    func test20HourlyDetail() {
        let app = launch(scene: "hourlyDetail")
        waitForNowContent(app)
        // `now.hourly` resolves to the "Stündlich" header button, and tapping
        // THAT only scrolls the strip back to its start. The card row sits
        // directly beneath it, so the sheet opens from a point below the
        // header. (An identifier on the strip itself is not an option: it sits
        // on a Group, which surfaces no element of its own.)
        let header = app.descendants(matching: .any)["now.hourly"].firstMatch
        scrollTo(header, in: app)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(
                dx: app.windows.firstMatch.frame.midX, dy: header.frame.maxY + 80
            ))
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

        // Same sheet, second half. One deliberate drag inside the sheet pulls
        // the medium detent up to .large (a plain swipe from the app's center
        // starts on the map behind it and pans that instead), then the usual
        // scroll walks down to the display toggles.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(2)
        let display = app.descendants(matching: .any)["map.layers.display"].firstMatch
        scrollTo(display, in: app, maxSwipes: 10)
        sleep(2)
        snapshot("22_map_layer_settings", timeWaitingForIdle: 0)
    }

    func test23AlertDetail() {
        let app = launch(scene: "nowRain")
        waitForNowContent(app)
        let badge = app.descendants(matching: .any)["now.alert"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "Alert badge never appeared")
        tapVisible(badge, in: app)
        sleep(3)
        snapshot("23_alert_detail", timeWaitingForIdle: 0)
    }

    func test24Settings() {
        let app = launch(scene: "customization")
        openSettings(app)
        sleep(2)
        snapshot("24_settings", timeWaitingForIdle: 0)
    }

    func test25SettingsNotifications() {
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

    func test26SettingsForecast() {
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

    func test27MemberCardDock() {
        let app = launch(scene: "customization")
        let card = openSettings(app)
        tapVisible(card, in: app)
        // The dock reveal is a two-stage animation (layout, then fade-in).
        sleep(3)
        snapshot("27_member_card_dock", timeWaitingForIdle: 0)
    }

    func test28Onboarding() {
        // One launch per step: the flow's own transitions are permission-gated,
        // and `-onboardingStep` drops straight onto each screen instead.
        let steps = [
            ("welcome", "28_onboarding_welcome"),
            ("features", "29_onboarding_features"),
            ("location", "30_onboarding_location"),
            ("notifications", "32_onboarding_notifications"),
            ("finale", "33_onboarding_finale"),
        ]
        for (step, name) in steps {
            let app = launch(scene: "onboarding", extraArguments: ["-onboardingStep", step])
            _ = app.wait(for: .runningForeground, timeout: 30)
            sleep(5)
            snapshot(name, timeWaitingForIdle: 0)
            app.terminate()
        }

        // The city step is only interesting with results on screen.
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

    func test34Places() {
        let app = launch(scene: "places")
        waitForNowContent(app)
        // Orte is the first tab; its title is localized, so index it.
        app.tabBars.buttons.element(boundBy: 0).tap()
        // Card conditions arrive in one batched request; the backdrops need a
        // moment more to settle into their sky.
        XCTAssertTrue(
            app.staticTexts["Essen"].waitForExistence(timeout: 30), "Orte list stayed empty"
        )
        sleep(5)
        snapshot("34_places", timeWaitingForIdle: 0)
    }

    // MARK: - Lock screen
    //
    // Last on purpose: these leave the simulator locked until `unlock()` runs,
    // and the private lock-button selector is the only way for a UI test to get
    // there (XCUIDevice exposes no lock button). The lock screen exposes NO
    // accessibility elements to XCTest (its tree is bare windows), so every
    // interaction there is a screen-coordinate tap, and those only land while
    // the display is lit: SpringBoard holds a touch lock while the backlight
    // is off, and on the simulator neither a notification nor a touch lights
    // it — only the lock button does.

    func test80LockNotifications() {
        let app = launch(scene: "lockNotifications")
        _ = app.wait(for: .runningForeground, timeout: 30)
        allowNotificationsIfAsked()
        pressLockButton()  // lock; the display goes dark
        // Both local notifications fire on a delay, after the lock.
        sleep(22)
        pressLockButton()  // light the lock screen, still locked
        // iOS stacks an app's lock-screen notifications behind a count badge.
        // One tap on the stack fans them out (a tap opens the app only when a
        // single card is showing, which is why both have to have landed first).
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80)).tap()
        sleep(3)
        snapshot("37_lock_notifications", timeWaitingForIdle: 0)
        unlock()
    }

    func test81LockLiveActivity() {
        let app = launch(scene: "lockLiveActivity")
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(6)
        pressLockButton()  // lock; the display goes dark
        sleep(6)
        pressLockButton()  // light the lock screen, still locked
        // The first card an app ever posts carries ActivityKit's consent
        // question ("Live-Aktivitäten von Oscar° erlauben?") inside itself,
        // with "Erlauben" / "Allow" at the card's lower right. Answer it so
        // the card shows its own layout. The Snapfile reinstalls the app per
        // language pass, so the question is there on every pass — a retry
        // pass (no reinstall) finds it answered, and this tap then opens the
        // app from the card instead; re-run that pass by hand.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.71, dy: 0.81)).tap()
        sleep(4)
        snapshot("38_lock_live_activity", timeWaitingForIdle: 0)
        unlock()
    }

    // MARK: - Lock screen helpers

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// The permission prompt only appears on the first run after an install.
    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN {'Allow', 'Erlauben', 'İzin Ver'}")
        ).firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }
    }

    /// XCUIDevice has no public lock button; `pressLockButton` is the private
    /// selector XCTest itself uses. It TOGGLES the display: from an unlocked,
    /// lit device it locks and darkens; from a dark locked one it lights the
    /// lock screen. Guarded, so a future SDK that drops it fails the lock
    /// scenes instead of crashing the whole run.
    private func pressLockButton() {
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else {
            XCTFail("pressLockButton is gone — the lock screen scenes need a new door")
            return
        }
        _ = XCUIDevice.shared.perform(selector)
        sleep(3)
    }

    /// From a lit lock screen back to an unlocked device, or every following
    /// test launches into a locked one. A drag up from the bottom edge: a
    /// swipe from mid-screen scrolls the notifications into Notification
    /// Center instead. No passcode on the simulator, so no code to enter.
    private func unlock() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.985))
            .press(
                forDuration: 0.1,
                thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            )
        sleep(2)
    }
}
