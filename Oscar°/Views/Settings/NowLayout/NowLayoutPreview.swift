import SwiftUI

/// The band above the layout list, under the real sky: the head with its
/// metrics at full size, or the whole page zoomed out to a minimap of real
/// cards (the onboarding collage's staged data) with a label beside every
/// section. On a wide window (iPad, the Duo unfolded, Mac) the minimap is
/// the two-column page: stage labels on the left, feed labels on the right.
/// Animates as the list below changes.
struct NowLayoutPreview: View {
    let part: NowLayoutSettingsView.Part

    @Environment(Weather.self) private var weather
    @Environment(Location.self) private var location
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var snapshotCache = AtmosphereSnapshotCache()
    private let settingsService = SettingService.shared

    private static let height: CGFloat = 260
    private static let mapInset: CGFloat = 12
    private static let calloutWidth: CGFloat = 150

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
        .background(AtmosphereSampler.skyGradient(snapshot: snapshot))
        .clipShape(.rect(cornerRadius: 26))
        .animation(.snappy, value: settingsService.nowSections)
        .animation(.snappy, value: settingsService.stageNowSections)
        .animation(.snappy, value: settingsService.headMetrics)
        // Decorative: the list below is the accessible surface, and the
        // values are spoken on the forecast page itself.
        .accessibilityHidden(true)
    }

    private var wideSize: CGSize? {
        presentation.forecastIsWide ? presentation.forecastSize : nil
    }

    /// The page scaled to fit the band and a label level with each section.
    private var pageMap: some View {
        let map = wideSize.map { PageMap(stage: settingsService.nowStageSections, feed: settingsService.nowFeedSections, size: $0) }
            ?? PageMap(stage: settingsService.nowPageSections, feed: [], size: nil)
        let labelColumns: CGFloat = map.isWide ? 2 : 1
        return GeometryReader { geometry in
            // Capped so a page of one or two sections doesn't balloon.
            let scale = min(
                (Self.height - 2 * Self.mapInset) / map.size.height,
                (geometry.size.width - labelColumns * (Self.calloutWidth + 3)) / map.size.width,
                0.3
            )
            HStack(alignment: .top, spacing: 3) {
                if map.isWide {
                    callouts(map.stage, in: map, scale: scale, mirrored: true)
                }
                MiniPage(map: map)
                    .frame(width: map.size.width, height: map.size.height, alignment: .top)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: map.size.width * scale, height: map.size.height * scale, alignment: .topLeading)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 5))
                callouts(map.isWide ? map.feed : map.stage, in: map, scale: scale, mirrored: false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func callouts(_ sections: [NowSection], in map: PageMap, scale: CGFloat, mirrored: Bool) -> some View {
        let alignment: Alignment = mirrored ? .topTrailing : .topLeading
        return ZStack(alignment: alignment) {
            ForEach(sections) { section in
                callout(section, mirrored: mirrored)
                    .offset(y: map.midY(of: section) * scale - 10)
                    .transition(.opacity)
            }
            if !mirrored, map.stage.isEmpty, map.feed.isEmpty {
                Text("Keine Abschnitte")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(.leading, 8)
                    .offset(y: (map.isWide ? PageMap.spacing : map.headHeight / 2) * scale - 10)
            }
        }
        .frame(width: Self.calloutWidth, alignment: alignment)
    }

    private func callout(_ section: NowSection, mirrored: Bool) -> some View {
        let leader = Rectangle()
            .frame(width: 16, height: 1)
            .opacity(0.6)
        return HStack(spacing: 6) {
            if !mirrored { leader }
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(section.tint.gradient, in: .rect(cornerRadius: 5))
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            if mirrored { leader }
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

/// The miniature's grid in full-size page points. Every block has a fixed
/// height, so the labels are placed by arithmetic instead of measuring the
/// scaled page. The phone page is one column as tall as its content; the
/// wide page is the window, the stage's map taking the spare height and the
/// feed running off the bottom like the real scroll.
private struct PageMap {
    static let phoneWidth: CGFloat = 390
    static let headHeight: CGFloat = 170
    static let compactHeadHeight: CGFloat = 150
    static let spacing: CGFloat = 20

    let size: CGSize
    let isWide: Bool
    let stageWidth: CGFloat
    let stage: [NowSection]
    let feed: [NowSection]
    private let mapHeight: CGFloat
    private let tops: [NowSection: CGFloat]

    var headHeight: CGFloat { isWide ? Self.compactHeadHeight : Self.headHeight }
    var feedWidth: CGFloat { size.width - stageWidth }

    init(stage: [NowSection], feed: [NowSection], size wide: CGSize?) {
        isWide = wide != nil
        self.stage = stage
        self.feed = feed
        let headHeight = isWide ? Self.compactHeadHeight : Self.headHeight
        let fixed = stage.reduce(0) { $0 + Self.spacing + ($1 == .map ? 0 : $1.pageHeight) } + Self.spacing
        mapHeight = wide.map { max(NowSection.map.pageHeight, $0.height - headHeight - fixed) } ?? 0

        var tops: [NowSection: CGFloat] = [:]
        var y = headHeight
        for section in stage {
            y += Self.spacing
            tops[section] = y
            y += section == .map ? mapHeight : section.pageHeight
        }
        let stageHeight = y + Self.spacing
        y = 0
        for section in feed {
            y += Self.spacing
            tops[section] = y
            y += section.pageHeight
        }
        self.tops = tops
        size = wide ?? CGSize(width: Self.phoneWidth, height: stageHeight)
        stageWidth = wide.map { $0.width - WideForecast.feedWidth(for: $0.width) } ?? Self.phoneWidth
    }

    func height(of section: NowSection) -> CGFloat {
        section == .map ? mapHeight : section.pageHeight
    }

    func midY(of section: NowSection) -> CGFloat {
        (tops[section] ?? 0) + height(of: section) / 2
    }
}

private extension NowSection {
    /// Title plus staged card, in page points; the map's minimum.
    var pageHeight: CGFloat {
        switch self {
        case .map: 280
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
    let map: PageMap

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: PageMap.spacing) {
                PreviewHead()
                    .frame(maxWidth: .infinity)
                    .frame(height: map.headHeight)
                ForEach(map.stage) { MiniSection(section: $0, width: map.stageWidth, height: map.height(of: $0)) }
            }
            .frame(width: map.stageWidth, alignment: .top)
            if map.isWide {
                VStack(alignment: .leading, spacing: PageMap.spacing) {
                    ForEach(map.feed) { MiniSection(section: $0, width: map.feedWidth, height: map.height(of: $0)) }
                }
                .padding(.top, PageMap.spacing)
                .frame(width: map.feedWidth, alignment: .top)
            }
        }
        .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.cardBackgroundStyle, stagedCardFill)
        // The grid's heights assume the default text size.
        .dynamicTypeSize(.large)
        .allowsHitTesting(false)
    }
}

/// One section's title and staged card at full size.
private struct MiniSection: View {
    let section: NowSection
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.leading)
            card
        }
        .frame(height: height, alignment: .top)
        .transition(.opacity)
    }

    @ViewBuilder
    private var card: some View {
        switch section {
        case .map:
            // Stands in for the live map: an empty tile filling the block.
            Color.clear
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
                .padding(.bottom)
        case .radar:
            PrecipitationSeriesChart(points: OnboardingSampleData.showerPoints, timeZone: .current)
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
            .frame(width: width, alignment: .leading)
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
            StationsCard(stations: OnboardingSampleData.stations, timeZone: .current) { _ in }
                .padding(.horizontal)
        }
    }
}
