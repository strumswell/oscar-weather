//
//  OnboardingExtrasStage.swift
//  Oscar°
//

import SwiftUI

/// The small things as the old feature collage: three endless columns of
/// real cards, tilted so they drift from bottom right to top left, fading
/// out where the text begins.
struct OnboardingExtrasStage: View {
    var body: some View {
        // The clear view takes the hero window; the much taller columns hang
        // off it and get clipped, so the stage never grows to their height.
        Color.clear
            .overlay {
                HStack(alignment: .top, spacing: 14) {
                    MarqueeColumn(speed: 24, initialOffset: -60) {
                        rainCard
                        gauges(0, 1)
                        RadarWidgetTile()
                        hourlyPair(0, 1)
                        CollageClimateCard()
                    }
                    MarqueeColumn(speed: 36, initialOffset: -220, width: 300) {
                        StationsCard(stations: OnboardingSampleData.stations, timeZone: .current) { _ in }
                        WatchTile(face: .now)
                        DailyWidgetTile()
                        gauges(1, 2)
                    }
                    MarqueeColumn(speed: 29, initialOffset: -130) {
                        CollageClimateCard()
                        gauges(2, 0)
                        hourlyPair(2, 3)
                        rainCard
                        WatchTile(face: .radar)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .rotationEffect(.degrees(-20))
            }
            .clipped()
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var rainCard: some View {
        PrecipitationSeriesChart(points: OnboardingSampleData.showerPoints, timeZone: .current)
            .padding(14)
            .frame(height: 110)
            .cardBackground()
            .clipShape(.rect(cornerRadius: 10))
            .cardBorder()
    }

    private func gauges(_ first: Int, _ second: Int) -> some View {
        HStack(spacing: 10) {
            AQIGaugeCard(metric: OnboardingSampleData.gauges[first])
            AQIGaugeCard(metric: OnboardingSampleData.gauges[second])
        }
    }

    private func hourlyPair(_ first: Int, _ second: Int) -> some View {
        HStack(spacing: 10) {
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[first])
            HourlyForecastCard(item: OnboardingSampleData.hourlyItems[second])
        }
    }
}

/// Loops its content upward at a constant speed. The content is laid out
/// `copies` times up front (every card exists before it scrolls into view),
/// and one linear repeatForever offset advances by exactly one copy, so the
/// seam is invisible. The offset is a pure transform: GPU-only scrolling.
private struct MarqueeColumn<Content: View>: View {
    let speed: Double
    var initialOffset: CGFloat = 0
    /// The stations card needs a wider column than gauges and tiles.
    var width: CGFloat = 230
    var copies = 3
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stackHeight: CGFloat = 0
    @State private var rolling = false

    private let spacing: CGFloat = 14

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<copies, id: \.self) { _ in
                VStack(spacing: spacing) { content }
            }
        }
        .frame(width: width)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stackHeight = $0 }
        .offset(y: initialOffset - (rolling ? copyStride : 0))
        .onChange(of: stackHeight) { restart() }
        .onChange(of: reduceMotion) { restart() }
    }

    /// One copy plus the gap after it.
    private var copyStride: CGFloat {
        (stackHeight + spacing) / CGFloat(copies)
    }

    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { rolling = false }
        guard stackHeight > 0, !reduceMotion else { return }
        withAnimation(.linear(duration: copyStride / speed).repeatForever(autoreverses: false)) {
            rolling = true
        }
    }
}

/// The radar widget: the map with the latest radar frame, its time, and the
/// place as a dot.
private struct RadarWidgetTile: View {
    var body: some View {
        Image("layer-radar-germany")
            .resizable()
            .scaledToFill()
            .frame(width: 158, height: 158)
            .overlay {
                Circle()
                    .fill(.blue)
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
            }
            .overlay(alignment: .topLeading) {
                Text(verbatim: "14:00")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.35), in: .rect(cornerRadius: 4))
                    .padding(10)
            }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}

/// The medium daily widget: the place and four days on the sky gradient.
private struct DailyWidgetTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Leipzig")
                .font(.subheadline.weight(.semibold))
            ForEach(OnboardingSampleData.dailyRows.prefix(4)) { row in
                HStack(spacing: 8) {
                    Text(row.weekday)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 42, alignment: .leading)
                    Image(row.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text(verbatim: "\(Int(row.low))°")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    TemperatureRangeView(
                        low: row.low,
                        high: row.high,
                        focusLow: nil,
                        focusHigh: nil,
                        minTemp: OnboardingSampleData.dailyTemperatureBounds.min,
                        maxTemp: OnboardingSampleData.dailyTemperatureBounds.max,
                        unit: "°C"
                    )
                    .frame(height: 4)
                    Text(verbatim: "\(Int(row.high))°")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.3, blue: 0.5), Color(red: 0.55, green: 0.66, blue: 0.86)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: .rect(cornerRadius: 22, style: .continuous)
        )
    }
}

/// The Oscar watch app, rebuilt from WatchNowView and WatchRainView with the
/// same fonts and layout, inside an Apple Watch case. Laid out at the real
/// 46 mm screen size, then scaled down for the collage.
private struct WatchTile: View {
    enum Face { case now, radar }

    let face: Face

    private static let screen = CGSize(width: 208, height: 248)
    private static let scale: CGFloat = 0.72
    /// Glass border plus case, around the screen on every side.
    private static let border: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background
            content
            statusBar
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .frame(width: Self.screen.width, height: Self.screen.height)
        .clipShape(.rect(cornerRadius: 38, style: .continuous))
        .padding(10)
        .background(.black, in: .rect(cornerRadius: 48, style: .continuous))
        .padding(6)
        .background(
            LinearGradient(colors: [Color(white: 0.36), Color(white: 0.16)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 54, style: .continuous)
        )
        .overlay(alignment: .trailing) {
            // Digital crown and side button.
            VStack(spacing: 22) {
                Capsule().frame(width: 9, height: 40)
                Capsule().frame(width: 6, height: 30)
            }
            .foregroundStyle(Color(white: 0.32))
            .offset(x: 6, y: -14)
        }
        .scaleEffect(Self.scale)
        .frame(
            width: (Self.screen.width + 2 * Self.border) * Self.scale,
            height: (Self.screen.height + 2 * Self.border) * Self.scale
        )
    }

    @ViewBuilder private var background: some View {
        switch face {
        case .now:
            // The watch's clear-day sky with the sun's glow.
            LinearGradient(
                colors: [Color(red: 0.33, green: 0.58, blue: 0.9), Color(red: 0.66, green: 0.8, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .topLeading) {
                RadialGradient(colors: [.white.opacity(0.85), .clear], center: .center, startRadius: 4, endRadius: 70)
                    .frame(width: 160, height: 160)
                    .offset(x: -20, y: -40)
            }
        case .radar:
            // Overcast while it rains.
            LinearGradient(
                colors: [Color(red: 0.19, green: 0.24, blue: 0.31), Color(red: 0.36, green: 0.39, blue: 0.43)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// The system clock top right and the app's page dots on the edge.
    private var statusBar: some View {
        ZStack(alignment: .topTrailing) {
            Text(verbatim: "10:09")
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 12)
                .padding(.trailing, 18)
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == pageIndex ? 1 : 0.4))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.trailing, 4)
            .frame(maxHeight: .infinity, alignment: .center)
            .offset(y: -40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var pageIndex: Int {
        face == .now ? 0 : 1
    }

    @ViewBuilder private var content: some View {
        switch face {
        case .now: nowPage
        case .radar: radarPage
        }
    }

    /// WatchNowView: place, big thin temperature, condition, the day's range.
    private var nowPage: some View {
        VStack(spacing: 0) {
            Text(verbatim: "Leipzig")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Spacer()
            Text(verbatim: "21°")
                .font(.system(size: 64, weight: .thin, design: .rounded))
            Text(WeatherConditionLabel.text(for: 0))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.top, -2)
            Spacer()
            HStack(spacing: 14) {
                rangeLabel("arrow.up", "27°")
                rangeLabel("arrow.down", "14°")
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .padding(.top, 44)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 2)
    }

    private func rangeLabel(_ systemImage: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
        }
    }

    /// WatchRainView: title, the nowcast headline, capsule bars, time axis.
    private var radarPage: some View {
        let points = Self.rainPoints
        let reference = RainNowcastSummary.reference(for: points.map(\.precipitation))

        return VStack(alignment: .leading, spacing: 4) {
            Text("Radar")
                .font(.system(size: 20, weight: .semibold))
            Text(RainNowcastSummary.headline(for: points, now: Self.rainStart))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(points, id: \.timestamp) { point in
                        RainNowcastBar(
                            value: point.precipitation,
                            reference: reference,
                            areaHeight: proxy.size.height,
                            fill: AnyShapeStyle(.linearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.vertical, 4)
            HStack {
                Text("Jetzt")
                Spacer()
                Text(points[points.count / 2].timestamp, format: .dateTime.hour().minute())
                Spacer()
                Text(points[points.count - 1].timestamp, format: .dateTime.hour().minute())
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 44)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let rainStart = Date.now

    /// Rain now, easing off over the next hour and a half.
    private static let rainPoints: [PrecipPoint] = (0..<18).map { step in
        PrecipPoint(
            timestamp: rainStart.addingTimeInterval(Double(step) * 300),
            precipitation: 1.6 - Double(step) * 0.04,
            isForecast: step > 0
        )
    }
}
