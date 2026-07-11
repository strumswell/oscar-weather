//
//  ScreenshotWidgetGallery.swift
//  Oscar°
//
//  Marketing composition for the widgets screenshot (`-screenshotScene
//  widgets`): the radar and daily-forecast home widgets rendered at their real
//  point sizes over a wallpaper-style backdrop. The widget entry views live
//  only in the widget target (adding them to the app would duplicate their
//  App Intents), so the small layouts are mirrored here — the radar composite
//  itself comes from the real RadarSnapshotRenderer.
//

import CoreLocation
import SwiftUI

struct ScreenshotWidgetGallery: View {
    private static let center = CLLocationCoordinate2D(
        latitude: ScreenshotFixtures.latitude,
        longitude: ScreenshotFixtures.longitude
    )

    /// Widget point sizes on the 6.9" iPhone class.
    private static let largeSize = CGSize(width: 364, height: 382)
    private static let mediumSize = CGSize(width: 364, height: 170)

    @State private var radar: RadarSnapshotRenderer.Rendered?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.65, saturation: 0.55, brightness: 0.35),
                         Color(hue: 0.62, saturation: 0.6, brightness: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                radarWidget
                    .frame(width: Self.largeSize.width, height: Self.largeSize.height)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 12)

                dailyWidget
                    .frame(width: Self.mediumSize.width, height: Self.mediumSize.height)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            }
            .accessibilityIdentifier("screenshot.widgetGallery")
        }
        .task {
            WidgetBasemapStore.registerRequestedStyle(MapBasemapStyle.fiord.rawValue)
            // First run on a fresh simulator: style + basemap tiles stream in
            // live, so retry until the composite (basemap included) succeeds.
            for _ in 0..<6 {
                await WidgetBasemapRenderer.refreshIfNeeded()
                radar = await RadarSnapshotRenderer.render(
                    center: Self.center,
                    size: WidgetBasemapStore.largeCompositeSize,
                    options: RadarWidgetRenderOptions()
                )
                if radar != nil { break }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // Mirrors RadarWidgetEntryView (widget target): filled map composite with
    // the frame-time badge in the top-left corner.
    @ViewBuilder
    private var radarWidget: some View {
        if let radar {
            Color.clear
                .overlay {
                    Image(uiImage: radar.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text(SettingService.formattedTime(radar.frameDate ?? .now))
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.6))
                        .clipShape(.rect(cornerRadius: 5))
                        .padding(15)
                }
        } else {
            ZStack {
                Color(red: 0.2, green: 0.22, blue: 0.28)
                ProgressView()
            }
        }
    }

    // Mirrors DailyForecastEntryView's medium layout (widget target).
    private var dailyWidget: some View {
        let days = Self.days
        let minTemp = days.map(\.low).min() ?? 0
        let maxTemp = days.map(\.high).max() ?? 30

        return VStack(alignment: .leading, spacing: 7) {
            Text("Leipzig")
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.bottom, 2)

            ForEach(days.prefix(4), id: \.weekday) { day in
                HStack(spacing: 10) {
                    Text(day.weekday)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 48, alignment: .leading)

                    Image(systemName: day.icon)
                        .symbolRenderingMode(.multicolor)
                        .font(.body)
                        .frame(width: 30, height: 22)

                    Text(roundTemperatureString(temperature: day.low))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, alignment: .trailing)

                    TemperatureRangeView(
                        low: day.low,
                        high: day.high,
                        focusLow: nil,
                        focusHigh: nil,
                        minTemp: minTemp,
                        maxTemp: maxTemp,
                        unit: "°C"
                    )
                    .frame(height: 6)

                    Text(roundTemperatureString(temperature: day.high))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                }
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        )
    }

    private struct GalleryDay {
        let weekday: String
        let icon: String
        let low: Double
        let high: Double
    }

    private static var days: [GalleryDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let icons = ["cloud.heavyrain.fill", "cloud.rain.fill", "cloud.sun.fill", "sun.max.fill"]
        let lows: [Double] = [13, 12, 13, 14]
        let highs: [Double] = [16, 19, 22, 24]
        let todayLabel = String(localized: "Heute")
        return (0..<4).map { index in
            let weekday = index == 0
                ? todayLabel
                : today.addingTimeInterval(Double(index) * 86_400)
                    .formatted(Date.FormatStyle().weekday(.abbreviated))
            return GalleryDay(weekday: weekday, icon: icons[index], low: lows[index], high: highs[index])
        }
    }
}
