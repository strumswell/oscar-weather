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
            "-hasCompletedOnboarding", "YES",
        ]
        app.launchArguments += extraArguments
        app.launch()
        return app
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
        // Composition: hourly strip at the top, the daily list filling the
        // rest. Scroll to the hourly section, then drag by the exact distance
        // that puts its top just under the status bar (slow drag + hold, so
        // no momentum overshoots the position).
        let hourly = app.descendants(matching: .any)["now.hourly"].firstMatch
        scrollTo(hourly, in: app)
        let targetY: CGFloat = 80
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

    // Parked scenes: rename back to test… to re-enable (the "skipped_" prefix
    // keeps XCTest from discovering them).
    func skipped_test08Customization() {
        let app = launch(scene: "customization")
        waitForNowContent(app)
        openSettingsTab(app)
        sleep(3)
        snapshot("08_customization", timeWaitingForIdle: 0)
    }

    func test09Widgets() {
        let app = launch(scene: "widgets")
        XCTAssertTrue(
            app.descendants(matching: .any)["screenshot.widgetGallery.ready"].waitForExistence(timeout: 30)
        )
        snapshot("09_widgets", timeWaitingForIdle: 0)
    }

    func skipped_test10Notifications() {
        let app = launch(scene: "notifications")
        waitForNowContent(app)
        openSettingsTab(app)

        let notificationsRow = app.descendants(matching: .any)["legal.notifications"].firstMatch
        XCTAssertTrue(notificationsRow.waitForExistence(timeout: 10))
        notificationsRow.tap()

        turnOn(toggle: "notifications.rainAlerts", in: app, allowsPermissionPrompt: true)
        turnOn(toggle: "notifications.weatherAlerts", in: app)
        turnOn(toggle: "notifications.liveRainStatus", in: app)
        sleep(2)
        snapshot("10_notifications", timeWaitingForIdle: 0)
    }

    // MARK: - Helpers

    /// Selects the settings tab (index-based: tab labels are localized and the
    /// snapshot run covers several languages).
    private func openSettingsTab(_ app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Tab bar not found")
        settingsTab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["legal.notifications"].waitForExistence(timeout: 10),
            "Settings tab did not open"
        )
    }

    private func turnOn(toggle identifier: String, in app: XCUIApplication, allowsPermissionPrompt: Bool = false) {
        let outer = app.switches[identifier].firstMatch
        guard outer.waitForExistence(timeout: 10) else {
            XCTFail("Toggle \(identifier) not found")
            return
        }
        if (outer.value as? String) == "1" { return }
        // SwiftUI nests the actual switch control inside the labeled row.
        let control = outer.switches.firstMatch.exists ? outer.switches.firstMatch : outer
        control.tap()

        if allowsPermissionPrompt {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 5) {
                // Notification permission alert: [Don't Allow, Allow].
                alert.buttons.element(boundBy: 1).tap()
            }
        }
        sleep(1)
    }
}
