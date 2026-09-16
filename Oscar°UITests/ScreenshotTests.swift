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

    // MARK: - Meteor regression checks

    func testHourlyMeteorNoticeOpensDetailsAndKeepsPlaceSelectionAvailable() {
        let app = launch(scene: "nowForecast", extraArguments: [
            "-screenshotMeteor", "YES",
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
        ])
        waitForNowContent(app)
        let meteor = app.buttons["now.meteor"].firstMatch
        let location = app.buttons["now.location"].firstMatch
        let hourly = app.descendants(matching: .any)["now.hourly"].firstMatch
        let strip = app.scrollViews["now.hourly.strip"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        let screenFrame = app.frame
        XCTAssertEqual(location.frame.midX, screenFrame.midX, accuracy: 3,
                       "The location should stay centered above the forecast")
        XCTAssertTrue(hourly.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(hourly.frame.minY, location.frame.maxY,
                             "The meteor notice belongs in the hourly section below the location")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        centerHourlyStrip(strip, in: app)
        for _ in 0..<5 {
            if isSufficientlyVisible(meteor, in: app) { break }
            strip.swipeLeft(velocity: .slow)
            usleep(400_000)
        }
        XCTAssertTrue(isSufficientlyVisible(meteor, in: app), "Meteor notice never entered the hourly viewport")
        // Accessibility frames can carry subpixel floating-point rounding.
        XCTAssertGreaterThanOrEqual(meteor.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(meteor.frame.height, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(meteor.frame.minY, hourly.frame.minY - 0.01)
        XCTAssertLessThanOrEqual(meteor.frame.maxY, hourly.frame.maxY + 0.01,
                                "The meteor notice should stay inside the existing hourly section")
        XCTAssertEqual(meteor.frame.width, 82, accuracy: 1,
                       "The meteor notice should use the same compact width as an hourly card")
        XCTAssertFalse(app.descendants(matching: .any)["now.alert.meteor"].exists)
        let hourlyScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hourlyScreenshot.name = "meteor-hourly"
        hourlyScreenshot.lifetime = .keepAlways
        add(hourlyScreenshot)

        tapVisible(meteor, in: app)
        let detail = app.descendants(matching: .any)["meteor.detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "Meteor details did not open")
        XCTAssertTrue(app.staticTexts["Perseiden"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Orte"].exists,
                       "Tapping the meteor must not activate the location control")
        let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailScreenshot.name = "meteor-details"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
        detail.swipeUp(velocity: .slow)
        usleep(800_000)
        let expandedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedScreenshot.name = "meteor-details-expanded"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)

        let close = app.buttons["meteor.detail.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5), "Meteor details did not close")

        let forecast = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'now.hourly.forecast'"))
            .firstMatch
        for _ in 0..<5 {
            if isSufficientlyVisible(forecast, in: app) { break }
            strip.swipeRight(velocity: .slow)
            usleep(400_000)
        }
        XCTAssertTrue(isSufficientlyVisible(forecast, in: app), "An ordinary forecast card must remain accessible")
        tapVisible(forecast, in: app)
        let hourlyDetail = app.navigationBars["Stündlich"].firstMatch
        XCTAssertTrue(hourlyDetail.waitForExistence(timeout: 5),
                      "Tapping an ordinary hour must still open hourly details")
        XCTAssertFalse(detail.exists, "An ordinary hour must not open meteor details")
        let closeHourly = hourlyDetail.buttons.firstMatch
        XCTAssertTrue(closeHourly.waitForExistence(timeout: 5))
        closeHourly.tap()
        XCTAssertTrue(hourlyDetail.waitForNonExistence(timeout: 5))

        // The place control sits just below the status bar, above the 120 pt
        // inset used for forecast cards. Check its own header area instead.
        let headerVisibleFrame = CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY + 60,
            width: screenFrame.width,
            height: screenFrame.height - 180
        )
        let isLocationHeaderVisible = {
            location.exists && !location.frame.isEmpty && headerVisibleFrame.contains(location.frame)
        }
        for _ in 0..<8 {
            if isLocationHeaderVisible() { break }
            app.swipeDown(velocity: .fast)
            usleep(400_000)
        }
        XCTAssertTrue(isLocationHeaderVisible(), "Could not return to the location header")
        location.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Orte"].waitForExistence(timeout: 5),
                      "Location selection should still open from the header")
        let leipzig = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Leipzig")).firstMatch
        XCTAssertTrue(leipzig.waitForExistence(timeout: 5))
        leipzig.tap()
        XCTAssertTrue(location.waitForExistence(timeout: 5), "Selecting a location should return to Now")
        scrollTo(hourly, in: app)
        XCTAssertTrue(meteor.waitForExistence(timeout: 10))
    }

    func testHourlyMeteorNoticeStaysSeparateFromWeatherWarning() {
        let app = launch(scene: "nowRain", extraArguments: ["-screenshotMeteor", "YES"])
        waitForNowContent(app)
        let meteor = app.buttons["now.meteor"].firstMatch
        let warning = app.descendants(matching: .any)["now.alert.weather"].firstMatch
        let hourly = app.descendants(matching: .any)["now.hourly"].firstMatch
        let strip = app.scrollViews["now.hourly.strip"].firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "The weather warning must remain visible")
        XCTAssertTrue(hourly.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(hourly.frame.minY, warning.frame.maxY - 0.01,
                                    "The weather warning must remain above the hourly section")
        XCTAssertFalse(app.descendants(matching: .any)["now.alert.meteor"].exists,
                       "Meteor information must no longer appear among weather warnings")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        centerHourlyStrip(strip, in: app)
        for _ in 0..<5 {
            if isSufficientlyVisible(meteor, in: app) { break }
            strip.swipeLeft(velocity: .slow)
            usleep(400_000)
        }
        XCTAssertTrue(isSufficientlyVisible(meteor, in: app), "Meteor notice never entered the hourly viewport")
        XCTAssertGreaterThanOrEqual(meteor.frame.minY, hourly.frame.minY - 0.01)
        XCTAssertLessThanOrEqual(meteor.frame.maxY, hourly.frame.maxY + 0.01)
        let warningScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        warningScreenshot.name = "meteor-warning-hourly"
        warningScreenshot.lifetime = .keepAlways
        add(warningScreenshot)

        tapVisible(meteor, in: app)
        let detail = app.descendants(matching: .any)["meteor.detail"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        detail.swipeUp(velocity: .slow)
        usleep(800_000)
        let detailScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailScreenshot.name = "meteor-warning-details-expanded"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    func testHourlyMeteorNoticeIsHiddenWithoutAnEvent() {
        let app = launch(scene: "nowForecast")
        waitForNowContent(app)
        XCTAssertTrue(app.buttons["now.location"].firstMatch.waitForExistence(timeout: 10))
        let hourly = app.descendants(matching: .any)["now.hourly"].firstMatch
        scrollTo(hourly, in: app)
        XCTAssertFalse(app.buttons["now.meteor"].firstMatch.waitForExistence(timeout: 3),
                       "A response without meteor events should not add a notice to the hourly forecast")
        XCTAssertFalse(app.descendants(matching: .any)["now.alert.meteor"].exists)
    }

    // MARK: - Helpers

    /// The hourly container can qualify for scrollTo with only its upper
    /// 120 pt visible. Center the strip before searching horizontally, so
    /// every card is also fully visible vertically.
    private func centerHourlyStrip(_ strip: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let visibleArea = safeArea(of: app)
        for _ in 0..<6 {
            // Stop once the strip fits: a few-point correction drag is short
            // enough to register as a tap on the card underneath.
            if strip.frame.minY >= visibleArea.minY, strip.frame.maxY <= visibleArea.maxY { break }
            let delta = strip.frame.midY - visibleArea.midY
            let startY: CGFloat = delta > 0 ? 0.75 : 0.25
            let endY = min(0.85, max(0.15, startY - delta / window.height))
            // The edge is outside the rain chart's interactive plot area.
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: startY))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: endY))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.4)
            usleep(400_000)
        }
        XCTAssertGreaterThanOrEqual(strip.frame.minY, visibleArea.minY - 0.01,
                                    "Hourly strip must be fully visible before horizontal scrolling")
        XCTAssertLessThanOrEqual(strip.frame.maxY, visibleArea.maxY + 0.01,
                                "Hourly strip must be fully visible before horizontal scrolling")
    }

    /// Opens Einstellungen via the button at the end of the forecast scroll
    /// (there is no settings tab; found by identifier since labels are localized).
    private func openSettingsTab(_ app: XCUIApplication) {
        let settingsButton = app.descendants(matching: .any)["now.settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings button not found")
        scrollTo(settingsButton, in: app, maxSwipes: 15)
        tapVisible(settingsButton, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["legal.notifications"].waitForExistence(timeout: 10),
            "Settings sheet did not open"
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
