import SwiftUI

/// The band above the layout list, under the real sky: the head with its
/// metrics at full size, or the whole page zoomed out to a minimap of real
/// cards (the onboarding collage's staged data) with a label beside every
/// section. Animates as the list below changes.
struct NowLayoutPreview: View {
    let part: NowLayoutSettingsView.Part

    @Environment(Weather.self) private var weather
    @Environment(Location.self) private var location
    @State private var snapshotCache = AtmosphereSnapshotCache()
    private let settingsService = SettingService.shared

    private static let height: CGFloat = 260
    private static let mapInset: CGFloat = 12

    var body: some View {
        let snapshot = weather.forecast.hourly != nil
            ? snapshotCache.snapshot(from: weather, at: location.coordinates)
            : .twilight
        Group {
            switch part {
            case .metrics: PreviewHead()
            case .sections: pageMap
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(AtmosphereSampler.skyGradient(snapshot: snapshot), in: .rect(cornerRadius: 26))
        .animation(.snappy, value: settingsService.nowSections)
        .animation(.snappy, value: settingsService.headMetrics)
        // Decorative: the list below is the accessible surface, and the
        // values are spoken on the forecast page itself.
        .accessibilityHidden(true)
    }

    /// The page scaled to fit the band and a label level with each section.
    private var pageMap: some View {
        let map = PageMap(sections: settingsService.nowSections)
        // Capped so a page of one or two sections doesn't balloon.
        let scale = min((Self.height - 2 * Self.mapInset) / map.height, 0.3)
        return HStack(alignment: .top, spacing: 3) {
            MiniPage(sections: map.sections)
                .frame(width: PageMap.width, height: map.height, alignment: .top)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: PageMap.width * scale, height: map.height * scale, alignment: .topLeading)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 5))
            ZStack(alignment: .topLeading) {
                ForEach(map.sections) { section in
                    callout(section)
                        .offset(y: map.midY(of: section) * scale - 10)
                        .transition(.opacity)
                }
                if map.sections.isEmpty {
                    Text("Keine Abschnitte")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(.leading, 8)
                        .offset(y: PageMap.headHeight * scale / 2 - 10)
                }
            }
            .frame(width: 150, alignment: .topLeading)
        }
    }

    private func callout(_ section: NowSection) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .frame(width: 16, height: 1)
                .opacity(0.6)
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(section.tint.gradient, in: .rect(cornerRadius: 5))
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .frame(height: 20)
        .foregroundStyle(.white)
        .shadow(radius: 2)
        // Rows sit about 33pt apart when every section shows.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// City, temperature and the chosen metrics, as the forecast page's head.
private struct PreviewHead: View {
    @Environment(Weather.self) private var weather
    @Environment(Location.self) private var location
    private let settingsService = SettingService.shared

    var body: some View {
        VStack(spacing: 4) {
            Text(location.name)
                .font(.title3.weight(.medium))
                .lineLimit(1)
            Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
                .font(.system(size: 88, weight: .thin))
            HStack(spacing: 18) {
                ForEach(settingsService.headMetrics) { metric in
                    if let value = metric.value(in: weather) {
                        Label(value, systemImage: metric.systemImage)
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minHeight: 20)
        }
        .foregroundStyle(.white)
        .shadow(radius: 3)
        .padding(.horizontal, 16)
    }
}

/// The miniature's vertical grid in full-size page points. Every block has
/// a fixed height, so the labels are placed by arithmetic instead of
/// measuring the scaled page.
private struct PageMap {
    static let width: CGFloat = 390
    static let headHeight: CGFloat = 170
    static let spacing: CGFloat = 20

    let sections: [NowSection]
    let tops: [CGFloat]
    let height: CGFloat

    init(sections: [NowSection]) {
        var tops: [CGFloat] = []
        var y = Self.headHeight
        for section in sections {
            y += Self.spacing
            tops.append(y)
            y += section.pageHeight
        }
        self.sections = sections
        self.tops = tops
        height = y + Self.spacing
    }

    func midY(of section: NowSection) -> CGFloat {
        guard let index = sections.firstIndex(of: section) else { return 0 }
        return tops[index] + section.pageHeight / 2
    }
}

private extension NowSection {
    /// Title plus staged card, in page points.
    var pageHeight: CGFloat {
        switch self {
        case .radar: 155
        case .hourly: 180
        case .daily: 220
        case .environment: 140
        case .climate: 130
        case .stations: 215
        }
    }
}

/// The forecast page at full size, built from the real cards with staged
/// values so every section shows whatever the weather. The caller scales it.
private struct MiniPage: View {
    let sections: [NowSection]

    /// A shower passing through over the next two hours.
    private static let showerPoints: [PrecipChartPoint] = (0...24).map { step in
        let progress = Double(step) / 24
        return PrecipChartPoint(
            date: Date(timeIntervalSinceReferenceDate: Double(step) * 300),
            value: 2.4 * exp(-pow((progress - 0.4) / 0.18, 2))
        )
    }

    /// Three stations around a mild day: cool night, warm afternoon.
    private static let sampleStations: [Components.Schemas.NearbyStation] = [
        ("Berlin Tempelhof", 5.8, 182.0, 0.0),
        ("Berlin Dahlem", 10.2, 224.0, -2.4),
        ("Potsdam", 27.9, 237.0, -1.3),
    ].map { name, distance, bearing, offset in
        let end = Date(timeIntervalSinceReferenceDate: 24 * 3600)
        let history = (0...24).map { hour in
            Components.Schemas.StationReading(
                time: end.addingTimeInterval(Double(hour - 24) * 3600),
                temperature_c: 13 + offset - 6 * cos(Double(hour + 3) / 24 * 2 * .pi))
        }
        return Components.Schemas.NearbyStation(
            id: name, name: name, source: "esoh", latitude: 52.5, longitude: 13.4,
            distance_km: distance, bearing_deg: bearing, last_report_at: end, current: history[24], history: history)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PageMap.spacing) {
            PreviewHead()
                .frame(maxWidth: .infinity)
                .frame(height: PageMap.headHeight)
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.leading)
                    card(for: section)
                }
                .frame(height: section.pageHeight, alignment: .top)
                .transition(.opacity)
            }
        }
        .environment(\.cardBackgroundStyle, collageCardFill)
        // The grid's heights assume the default text size.
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func card(for section: NowSection) -> some View {
        switch section {
        case .radar:
            PrecipitationSeriesChart(points: Self.showerPoints, timeZone: .gmt)
                .padding(16)
                .frame(height: 120)
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
        case .hourly:
            // Runs off the edge like the scrolling strip.
            HStack(spacing: 12) {
                ForEach(OnboardingSampleData.hourlyItems.prefix(5)) { HourlyForecastCard(item: $0) }
            }
            .font(.system(size: 18))
            .padding(.leading)
            .frame(width: PageMap.width, alignment: .leading)
            .clipped()
        case .daily:
            CollageDailyCard()
                .padding(.horizontal)
        case .environment:
            HStack(spacing: 14) {
                ForEach(OnboardingSampleData.gauges) { AQIGaugeCard(metric: $0) }
            }
            .font(.system(size: 18))
            .padding(.horizontal)
        case .climate:
            CollageClimateCard()
                .padding(.horizontal)
        case .stations:
            StationsCard(stations: Self.sampleStations, timeZone: .gmt) { _ in }
                .padding(.horizontal)
        }
    }
}
