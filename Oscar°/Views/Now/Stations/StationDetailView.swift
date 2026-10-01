import Charts
import SwiftUI

/// Tap-through for "Messstationen": one station's readings and its last 24 h. The chips
/// switch between all nearby stations; everything comes from `weather.stations`, no refetch.
struct StationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Weather.self) private var weather
    @State private var selectedID: String

    init(initialID: String) {
        _selectedID = State(initialValue: initialID)
    }

    var body: some View {
        let stations = weather.stations
        let station = stations.first { $0.id == selectedID } ?? stations.first
        NavigationStack {
            ScrollView {
                if let station {
                    let frame = StationChartFrame(end: station.last_report_at, weather: weather)
                    VStack(alignment: .leading, spacing: 16) {
                        if stations.count > 1 {
                            StationChips(stations: stations, selectedID: $selectedID)
                        }
                        StationHeader(
                            id: station.id,
                            name: station.name,
                            subtitle: [station.current.weather_code.map(WeatherConditionLabel.text(for:)),
                                       stationSubtitle(station, timeZone: weather.forecast.locationTimeZone),
                                       reportingInterval(station.history)].compactMap(\.self).joined(separator: " · "))
                        StationValueGrid(station: station)
                        StationTemperatureChart(history: station.history, frame: frame)
                        StationWindChart(history: station.history, frame: frame)
                        if station.precipitation_24h_mm != nil {
                            StationPrecipitationChart(
                                history: station.history, frame: frame, total: station.precipitation_24h_mm)
                        }
                        StationPressureChart(history: station.history, frame: frame)
                        StationFooter()
                    }
                    .padding()
                } else {
                    Text("Gerade keine Messwerte in der Nähe.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Messstationen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: dismiss.callAsFunction)
                }
            }
        }
        // White ink like the hourly sheet, which assumes dark too.
        .preferredColorScheme(.dark)
    }
}

/// How often the station reports, from the typical gap between its temperature readings:
/// "alle 10 Min.", "stündlich", "alle 3 Std.", or "unregelmäßig" when fewer than three in
/// four gaps match it (some secondary stations report in bursts). Nil with too few readings.
private func reportingInterval(_ history: [Components.Schemas.StationReading]) -> String? {
    let times = history.filter { $0.temperature_c != nil }.map(\.time)
    guard times.count > 2 else { return nil }
    let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }.sorted()
    let typical = gaps[gaps.count / 2]
    let regular = gaps.filter { abs($0 - typical) <= typical * 0.2 }.count
    guard regular * 4 >= gaps.count * 3 else { return String(localized: "unregelmäßig") }
    let minutes = Int((typical / 60).rounded())
    switch minutes {
    case ..<50: return String(localized: "alle \(minutes) Min.")
    case 50..<90: return String(localized: "stündlich")
    default: return String(localized: "alle \(Int((Double(minutes) / 60).rounded())) Std.")
    }
}

private struct StationChips: View {
    let stations: [Components.Schemas.NearbyStation]
    @Binding var selectedID: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(stations) { station in
                    let selected = station.id == selectedID
                    Button {
                        selectedID = station.id
                    } label: {
                        Text(verbatim: "\(station.name) · \(station.distance_km.formatted(.number.precision(.fractionLength(1)))) km")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                            .background(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.thinMaterial), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct StationHeader: View {
    let id: String
    let name: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.title2.bold())
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            FavoriteStar(id: id)
        }
    }
}

/// Starring winds the star up, pops it gold with a glow, two rings and a spray of sparks;
/// unstarring just swaps back.
private struct FavoriteStar: View {
    let id: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts new favorites only, so switching chips never replays the burst.
    @State private var bursts = 0

    private struct Pop {
        var scale: CGFloat = 1
        var angle: Double = 0
    }

    private static let gold = LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let settings = SettingService.shared
        let isFavorite = settings.favoriteStationIDs.contains(id)
        Button {
            withAnimation(.bouncy) {
                if isFavorite {
                    settings.favoriteStationIDs.removeAll { $0 == id }
                } else {
                    settings.favoriteStationIDs.append(id)
                    bursts += 1
                }
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFavorite ? AnyShapeStyle(Self.gold) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                // Squash and twist back, then snap past full size and settle with a wobble.
                .keyframeAnimator(initialValue: Pop(), trigger: reduceMotion ? 0 : bursts) { content, pop in
                    content.scaleEffect(pop.scale).rotationEffect(.degrees(pop.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(0.7, duration: 0.1)
                        SpringKeyframe(1.45, duration: 0.16, spring: .snappy)
                        SpringKeyframe(1, duration: 0.6, spring: .bouncy(extraBounce: 0.25))
                    }
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(-18, duration: 0.1)
                        SpringKeyframe(14, duration: 0.16, spring: .snappy)
                        SpringKeyframe(0, duration: 0.6, spring: .bouncy(extraBounce: 0.3))
                    }
                }
                .background {
                    if !reduceMotion { StarBurst(trigger: bursts) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Favorit"))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .sensoryFeedback(trigger: settings.favoriteStationIDs) { old, new in
            new.count > old.count ? .impact(flexibility: .soft) : .selection
        }
    }
}

/// Fires on the star's release (after its 0.1 s wind-up): a flash of glow, two rings,
/// then sparks that fly out, spin, drift down a little and fade.
private struct StarBurst: View {
    let trigger: Int

    private struct Spark {
        var distance: CGFloat = 0
        var scale: CGFloat = 0
        var spin: Double = 0
        var fall: CGFloat = 0
        var opacity: Double = 0
    }

    private struct SparkStyle {
        let angle: Double
        let reach: CGFloat
        let delay: Double
        let size: CGFloat
        let isStar: Bool
        let color: Color
    }

    private static let release = 0.1

    /// Fixed jitter per spark, so the spray looks hand-thrown but never random.
    private static let sparks: [SparkStyle] = (0..<14).map { index -> SparkStyle in
        let angleJitter: [Double] = [0, 9, -6, 4]
        let reachJitter: [CGFloat] = [0, 5, -3, 7, 2]
        let starSizes: [CGFloat] = [7, 5, 9]
        let dotSizes: [CGFloat] = [3, 2.5, 4]
        let colors: [Color] = [.yellow, .orange, .white]
        let isStar = index.isMultiple(of: 2)
        return SparkStyle(
            angle: Double(index) * 360 / 14 + angleJitter[index % 4],
            reach: (isStar ? 30 : 21) + reachJitter[index % 5],
            delay: Double(index % 3) * 0.03,
            size: (isStar ? starSizes : dotSizes)[index % 3],
            isStar: isStar,
            color: colors[index % 3])
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.yellow.opacity(0.9), .orange.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
                .blendMode(.plusLighter)
                .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, glow in
                    content.scaleEffect(glow.scale).opacity(glow.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.3, duration: Self.release)
                        CubicKeyframe(1.3, duration: 0.35)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: Self.release)
                        LinearKeyframe(0.7, duration: 0.05)
                        CubicKeyframe(0, duration: 0.45)
                    }
                }
            ring(delay: 0, size: 30, lineWidth: 2)
            ring(delay: 0.1, size: 40, lineWidth: 1)
            ForEach(Self.sparks.indices, id: \.self) { index in
                spark(Self.sparks[index])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(delay: Double, size: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(AngularGradient(colors: [.yellow, .orange, .yellow], center: .center), lineWidth: lineWidth)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, ring in
                content.scaleEffect(ring.scale).opacity(ring.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: Self.release + delay)
                    CubicKeyframe(1.5, duration: 0.5)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: Self.release + delay)
                    LinearKeyframe(0.9, duration: 0.04)
                    CubicKeyframe(0, duration: 0.46)
                }
            }
    }

    private func spark(_ style: SparkStyle) -> some View {
        let start = Self.release + style.delay
        return Group {
            if style.isStar {
                Image(systemName: "star.fill").font(.system(size: style.size))
            } else {
                Circle().frame(width: style.size, height: style.size)
            }
        }
        .foregroundStyle(style.color)
        .shadow(color: .orange.opacity(0.7), radius: 2)
        .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, spark in
            content
                .scaleEffect(spark.scale)
                .rotationEffect(.degrees(spark.spin))
                .offset(y: -spark.distance)
                .rotationEffect(.degrees(style.angle))
                .offset(y: spark.fall)
                .opacity(spark.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.distance) {
                LinearKeyframe(4, duration: start)
                SpringKeyframe(style.reach, duration: 0.5, spring: .snappy)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0, duration: start)
                SpringKeyframe(1, duration: 0.18, spring: .bouncy)
                CubicKeyframe(0.1, duration: 0.5)
            }
            KeyframeTrack(\.spin) {
                LinearKeyframe(0, duration: start)
                CubicKeyframe(style.isStar ? 160 : 0, duration: 0.7)
            }
            KeyframeTrack(\.fall) {
                LinearKeyframe(0, duration: start + 0.25)
                CubicKeyframe(9, duration: 0.45)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: start)
                LinearKeyframe(1, duration: 0.03)
                LinearKeyframe(1, duration: 0.32)
                LinearKeyframe(0, duration: 0.35)
            }
        }
    }
}

private struct StationValueGrid: View {
    let station: Components.Schemas.NearbyStation

    var body: some View {
        let units = StationUnits()
        let current = station.current
        let direction = current.wind_direction_deg.map { " \(compassDirection($0))" } ?? ""
        DetailCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 14) {
                StationValue(label: "Temperatur", value: units.temperatureString(current.temperature_c))
                StationValue(label: "Taupunkt", value: units.temperatureString(current.dew_point_c))
                StationValue(label: "Luftfeuchtigkeit", value: current.humidity_pct.map { "\(Int($0.rounded())) %" } ?? "–")
                StationValue(label: "Wind", value: units.windString(current.wind_speed_ms) + direction)
                StationValue(label: "Böen", value: units.windString(current.wind_gust_ms))
                StationValue(label: "Luftdruck", value: current.pressure_hpa.map { "\(Int($0.rounded())) hPa" } ?? "–")
            }
        }
    }
}

private struct StationValue: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Gemessene Werte …" plus the source marks; the licence details live on the data-provider page.
private struct StationFooter: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Gemessene Werte der nächstgelegenen Wetterstationen, keine Vorhersage.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 22) {
                ProviderLogo(asset: "logo-eumetnet", height: 28)
                ProviderLogo(asset: "logo-dwd", height: 28)
                ProviderLogo(asset: "logo-oscar-server", height: 24)
            }
            .foregroundStyle(.white)
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "EUMETNET, DWD & Oscar Server"))
        }
        .padding(.top, 8)
    }
}

/// The 24 h window every chart of one station shares, with the forecast's night hours.
struct StationChartFrame {
    let window: ClosedRange<Date>
    let nightRanges: [ClosedRange<Date>]

    @MainActor
    init(end: Date, weather: Weather) {
        let window = end.addingTimeInterval(-24 * 3600)...end
        let hourly = weather.forecast.hourly
        self.window = window
        nightRanges = HourlyTimelineModel.nightRanges(times: hourly?.time ?? [], isDay: hourly?.is_day ?? [])
            .map { Date(timeIntervalSince1970: $0.lowerBound)...Date(timeIntervalSince1970: $0.upperBound) }
            .filter { $0.overlaps(window) }
            .map { max($0.lowerBound, window.lowerBound)...min($0.upperBound, window.upperBound) }
    }
}

/// Title and trailing summary over a chart, legend below.
private struct StationChartCard<Content: View>: View {
    let title: LocalizedStringResource
    var summary: String?
    var legend: [StationChart.Line] = []
    @ViewBuilder let content: Content

    var body: some View {
        DetailCard {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                if let summary {
                    Text(verbatim: summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content
                .frame(height: 180)
            if legend.count > 1 {
                HStack(spacing: 12) {
                    ForEach(legend.reversed(), id: \.label) { line in
                        StationLegendItem(color: line.color, label: LocalizedStringKey(line.label))
                    }
                }
            }
        }
    }
}

private func points(_ history: [Components.Schemas.StationReading], _ value: (Components.Schemas.StationReading) -> Double?) -> [StationChart.Point] {
    history.compactMap { reading in value(reading).map { .init(time: reading.time, value: $0) } }
}

/// Joint min/max padded like the hourly lenses' `paddedDomain`.
private func paddedDomain(_ lines: [StationChart.Line], from lowerPin: Double? = nil, minimumPad: Double = 0.5) -> ClosedRange<Double> {
    let values = lines.flatMap { $0.points.map(\.value) }
    guard var low = values.min(), var high = values.max() else { return (lowerPin ?? 0)...((lowerPin ?? 0) + 1) }
    let pad = max((high - low) * 0.08, minimumPad)
    low = lowerPin ?? (low - pad)
    high += pad
    return high > low ? low...high : low...(low + 1)
}

private struct StationTemperatureChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let units = StationUnits()
        let symbol = units.temperatureUnit.symbol
        let lines = [
            StationChart.Line(points: points(history) { $0.dew_point_c.map(units.temperature) }, color: .mint, width: 1.5,
                              label: String(localized: "Taupunkt")),
            StationChart.Line(points: points(history) { $0.temperature_c.map(units.temperature) }, color: .orange,
                              label: String(localized: "Temperatur")),
        ]
        StationChartCard(title: "Temperatur und Taupunkt", legend: lines) {
            StationChart(
                frame: frame, lines: lines, yDomain: paddedDomain(lines),
                valueFormat: { "\($0.formatted(.number.precision(.fractionLength(1))))\(symbol)" },
                extremeFormat: { "\(Int($0.rounded()))°" }, showsExtremes: true)
        }
    }
}

private struct StationWindChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let units = StationUnits()
        let unit = units.windUnit.displayUnit
        // Gusts sit behind the mean like the hourly lens' higher-altitude lines.
        let lines = [
            StationChart.Line(points: points(history) { $0.wind_gust_ms.map(units.wind) }, color: .teal.mix(with: .black, by: 0.4),
                              width: 1.5, label: String(localized: "Böen")),
            StationChart.Line(points: points(history) { $0.wind_speed_ms.map(units.wind) }, color: .teal,
                              label: String(localized: "Wind")),
        ]
        // One arrow per 3 h keeps the direction readable at hourly and 10-min cadence.
        let arrows = history.compactMap { reading -> StationChart.Point? in
            guard let direction = reading.wind_direction_deg,
                  Int(reading.time.timeIntervalSince1970) % (3 * 3600) == 0 else { return nil }
            return .init(time: reading.time, value: direction)
        }
        if lines.contains(where: { !$0.points.isEmpty }) {
            StationChartCard(title: "Wind", summary: unit, legend: lines) {
                StationChart(
                    frame: frame, lines: lines, yDomain: paddedDomain(lines, from: 0),
                    valueFormat: { "\(Int($0.rounded())) \(unit)" }, arrows: arrows)
            }
        }
    }
}

private struct StationPrecipitationChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame
    let total: Double?

    var body: some View {
        let units = StationUnits()
        let unit = units.precipitationUnit
        let bars = hourlyBars(units)
        let peak = max(bars.map(\.value).max() ?? 0, units.precipitation(1))
        StationChartCard(title: "Niederschlag", summary: String(localized: "\(units.precipitationString(total)) in 24h")) {
            StationChart(
                frame: frame, lines: [], bars: bars, yDomain: 0...(peak * 1.08),
                valueFormat: { "\($0.formatted(.number.precision(.fractionLength(1)))) \(unit)" })
        }
    }

    /// Sub-hourly sums fold into the hour they end in: hourly bars like the hourly view
    /// instead of 144 ten-minute slivers.
    private func hourlyBars(_ units: StationUnits) -> [StationChart.Bar] {
        var bars: [StationChart.Bar] = []
        for reading in history {
            guard let mm = reading.precipitation_mm else { continue }
            let value = units.precipitation(mm)
            let minutes = reading.precipitation_period_min ?? 60
            guard minutes < 60 else {
                bars.append(.init(start: reading.time.addingTimeInterval(-TimeInterval(minutes * 60)), end: reading.time,
                                  value: value, minutes: minutes))
                continue
            }
            let hourEnd = Date(timeIntervalSince1970: (reading.time.timeIntervalSince1970 / 3600).rounded(.up) * 3600)
            if let last = bars.last, last.end == hourEnd {
                bars[bars.count - 1] = .init(start: last.start, end: hourEnd, value: last.value + value, minutes: 60)
            } else {
                bars.append(.init(start: hourEnd.addingTimeInterval(-3600), end: hourEnd, value: value, minutes: 60))
            }
        }
        return bars
    }
}

private struct StationPressureChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let lines = [StationChart.Line(points: points(history) { $0.pressure_hpa }, color: .purple, label: String(localized: "Luftdruck"))]
        if !lines[0].points.isEmpty {
            StationChartCard(title: "Luftdruck", summary: threeHourTrend(lines[0].points)) {
                StationChart(
                    frame: frame, lines: lines, yDomain: paddedDomain(lines, minimumPad: 2),
                    valueFormat: { "\($0.formatted(.number.grouping(.never).precision(.fractionLength(1)))) hPa" },
                    extremeFormat: { "\(Int($0.rounded()))" }, showsExtremes: true)
            }
        }
    }

    /// "+1,2 hPa in 3h" against the reading closest to three hours before the newest.
    private func threeHourTrend(_ pressures: [StationChart.Point]) -> String? {
        guard let last = pressures.last else { return nil }
        let target = last.time.addingTimeInterval(-3 * 3600)
        guard let earlier = pressures.min(by: { abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target)) }),
              abs(earlier.time.timeIntervalSince(target)) <= 1800 else { return nil }
        let delta = (last.value - earlier.value).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(delta) hPa in 3h")
    }
}

/// A station's last 24 h in the hourly palette: default y axis, and a rule plus
/// tooltip only while the chart is touched.
struct StationChart: View {
    struct Point {
        let time: Date
        let value: Double
    }

    struct Line {
        let points: [Point]
        let color: Color
        var width: CGFloat = 2
        let label: String
    }

    struct Bar {
        let start: Date
        let end: Date
        let value: Double
        let minutes: Int
    }

    let frame: StationChartFrame
    /// The last line is the primary: extremes and arrows ride it.
    let lines: [Line]
    var bars: [Bar] = []
    let yDomain: ClosedRange<Double>
    let valueFormat: (Double) -> String
    var extremeFormat: ((Double) -> String)?
    var showsExtremes = false
    /// Wind direction (degrees, from) at 3 h steps.
    var arrows: [Point] = []

    @State private var selectedDate: Date?

    /// Longer than any station's report interval: a wider hole in a series is missing data.
    private static let maxGap: TimeInterval = 3.5 * 3600

    var body: some View {
        Chart {
            backgroundMarks
            lineMarks
            if let primary = lines.last {
                arrowMarks(on: primary)
                if showsExtremes { extremeMarks(on: primary) }
            }
            if let selectedDate {
                RuleMark(x: .value("Auswahl", selectedDate))
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(.init(lineWidth: 2))
                    .annotation(position: .topTrailing, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        tooltip(at: selectedDate)
                    }
            }
        }
        .chartXScale(domain: frame.window)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            // The shared 6 h marks; a label too close to the right edge would clip, so it skips.
            AxisMarks(values: tickDates) { value in
                AxisValueLabel {
                    // Labels hang right of their tick and need ~3 h of the 24 h width.
                    if let date = value.as(Date.self), frame.window.upperBound.timeIntervalSince(date) >= 3.5 * 3600 {
                        Text(HourlyChartUtilities.hourString(from: date))
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        }
        // Default axis minus the thousands separator ("1020", not "1.020").
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.grouping(.never))
            }
        }
        .chartBackground { proxy in
            GeometryReader { geometry in
                if !bars.isEmpty, let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    Canvas { context, _ in drawBars(in: context, proxy: proxy, plot: plot) }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Verlauf der letzten 24 Stunden"))
        .accessibilityValue(Text(verbatim: accessibilitySummary))
    }

    @ChartContentBuilder
    private var backgroundMarks: some ChartContent {
        ForEach(frame.nightRanges, id: \.lowerBound) { night in
            RectangleMark(xStart: .value("Nacht", night.lowerBound), xEnd: .value("Nacht", night.upperBound))
                .foregroundStyle(.black.opacity(0.1))
        }
        HourlyChartUtilities.daySeparatorMarks(time: hourStamps)
    }

    /// The hourly strip's bars: a gap between neighbours and only the top corners rounded,
    /// which chart marks can't do. Drawn behind the marks so the selection stays on top.
    private func drawBars(in context: GraphicsContext, proxy: ChartProxy, plot: CGRect) {
        guard let base = proxy.position(forY: 0.0) else { return }
        for bar in bars where bar.value > 0 {
            guard let start = proxy.position(forX: max(bar.start, frame.window.lowerBound)),
                  let end = proxy.position(forX: min(bar.end, frame.window.upperBound)),
                  let top = proxy.position(forY: bar.value), end - start > 2 else { continue }
            let rect = CGRect(x: plot.minX + start + 1, y: plot.minY + top, width: end - start - 2, height: base - top)
            let radius = min(4, rect.width / 2, rect.height)
            context.fill(Path(roundedRect: rect, cornerRadii: .init(topLeading: radius, topTrailing: radius)),
                         with: .color(Color.hourlyRain.opacity(0.75)))
        }
    }

    /// One series per gap-free run, so a hole in the data stays a hole.
    private var runs: [(id: String, line: Line, points: [Point])] {
        lines.enumerated().flatMap { index, line in
            Self.segments(line.points).enumerated().map { segment, points in ("\(index)-\(segment)", line, points) }
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(runs, id: \.id) { run in
            // A reading between two gaps has no line to sit on.
            if run.points.count == 1, let point = run.points.first {
                PointMark(x: .value("Zeit", point.time), y: .value(run.line.label, point.value))
                    .symbolSize(24)
                    .foregroundStyle(run.line.color)
            }
            ForEach(run.points, id: \.time) { point in
                LineMark(x: .value("Zeit", point.time), y: .value(run.line.label, point.value),
                         series: .value("Reihe", run.id))
                    .foregroundStyle(run.line.color)
                    .lineStyle(StrokeStyle(lineWidth: run.line.width, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private func arrowMarks(on primary: Line) -> some ChartContent {
        let placed = arrows.compactMap { arrow in Self.sample(primary.points, at: arrow.time).map { (arrow, $0) } }
        ForEach(placed, id: \.0.time) { arrow, value in
            PointMark(x: .value("Zeit", arrow.time), y: .value(primary.label, value))
                .symbol {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.teal)
                        .shadow(color: .teal.mix(with: .black, by: 0.35), radius: 0.8)
                        .rotationEffect(.degrees(arrow.value + 180))
                }
        }
    }

    @ChartContentBuilder
    private func extremeMarks(on primary: Line) -> some ChartContent {
        ForEach(extremes(of: primary), id: \.point.time) { extreme in
            PointMark(x: .value("Zeit", extreme.point.time), y: .value(primary.label, extreme.point.value))
                .symbolSize(30)
                .foregroundStyle(primary.color)
                .annotation(position: extreme.isHigh ? .top : .bottom, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    Text(verbatim: (extremeFormat ?? valueFormat)(extreme.point.value))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                }
        }
    }

    /// The tooltip reads the readings at the finger.
    private func tooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                StationValueRow(color: line.color, label: LocalizedStringKey(line.label),
                                text: Self.sample(line.points, at: date).map(valueFormat) ?? "--")
            }
            if !bars.isEmpty {
                let bar = bars.last { $0.start < date && date <= $0.end }
                StationValueRow(color: .hourlyRain, label: "Regen",
                                text: bar.map { "\(valueFormat($0.value)) / \($0.minutes / 60) h" } ?? "--")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial.opacity(0.9))
        .clipShape(.rect(cornerRadius: 8))
        .shadow(radius: 4)
    }

    private var tickDates: [Date] {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: frame.window.lowerBound)
        components.hour = ((components.hour ?? 0) / 6) * 6
        guard let first = calendar.date(from: components) else { return [] }
        return stride(from: 0, through: 30, by: 6).compactMap { calendar.date(byAdding: .hour, value: $0, to: first) }
            .filter { frame.window.contains($0) }
    }

    /// Hourly stamps across the window, for the shared day-separator marks.
    private var hourStamps: [Double] {
        Array(stride(from: frame.window.lowerBound.timeIntervalSince1970, through: frame.window.upperBound.timeIntervalSince1970, by: 3600))
    }

    private var accessibilitySummary: String {
        lines.reversed().compactMap { line in
            line.points.last.map { "\(line.label) \(valueFormat($0.value))" }
        }.joined(separator: ", ")
    }

    /// High and low of a series, only when they're worth a label.
    private func extremes(of line: Line) -> [(point: Point, isHigh: Bool)] {
        guard let high = line.points.max(by: { $0.value < $1.value }),
              let low = line.points.min(by: { $0.value < $1.value }),
              high.value - low.value >= (yDomain.upperBound - yDomain.lowerBound) / 4 else { return [] }
        return [(high, true), (low, false)]
    }

    /// Runs of readings without a gap wider than `maxGap`.
    private static func segments(_ points: [Point]) -> [[Point]] {
        var runs: [[Point]] = []
        for point in points {
            if let last = runs.last?.last, point.time.timeIntervalSince(last.time) <= maxGap {
                runs[runs.count - 1].append(point)
            } else {
                runs.append([point])
            }
        }
        return runs
    }

    /// Linear between the neighbouring readings; nil outside the series or across a gap.
    private static func sample(_ points: [Point], at date: Date) -> Double? {
        guard let upper = points.firstIndex(where: { $0.time >= date }) else { return nil }
        if points[upper].time == date || upper == 0 {
            return points[upper].time.timeIntervalSince(date) <= 600 ? points[upper].value : nil
        }
        let lower = points[upper - 1], next = points[upper]
        let span = next.time.timeIntervalSince(lower.time)
        guard span <= maxGap else { return nil }
        return lower.value + (next.value - lower.value) * date.timeIntervalSince(lower.time) / span
    }
}

private struct StationLegendItem: View {
    let color: Color
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StationValueRow: View {
    let color: Color
    let label: LocalizedStringKey
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(Text(label)): \(text)")
                .font(.caption2)
                .foregroundStyle(.white)
        }
    }
}
