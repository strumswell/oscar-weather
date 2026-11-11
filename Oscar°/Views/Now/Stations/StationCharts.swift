//
//  StationCharts.swift
//  Oscar°
//

import Charts
import SwiftUI

struct StationChartFrame {
    let window: ClosedRange<Date>
    let nightRanges: [ClosedRange<Date>]
    let timeZone: TimeZone

    @MainActor
    init(end: Date, weather: Weather) {
        let window = end.addingTimeInterval(-24 * 3600)...end
        let hourly = weather.forecast.hourly
        self.window = window
        timeZone = weather.forecast.locationTimeZone
        nightRanges = HourlyTimelineModel.nightRanges(times: hourly?.time ?? [], isDay: hourly?.is_day ?? [])
            .map { Date(timeIntervalSince1970: $0.lowerBound)...Date(timeIntervalSince1970: $0.upperBound) }
            .filter { $0.overlaps(window) }
            .map { max($0.lowerBound, window.lowerBound)...min($0.upperBound, window.upperBound) }
    }
}

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

private func paddedDomain(_ lines: [StationChart.Line], from lowerPin: Double? = nil, minimumPad: Double = 0.5) -> ClosedRange<Double> {
    let values = lines.flatMap { $0.points.map(\.value) }
    guard var low = values.min(), var high = values.max() else { return (lowerPin ?? 0)...((lowerPin ?? 0) + 1) }
    let pad = max((high - low) * 0.08, minimumPad)
    low = lowerPin ?? (low - pad)
    high += pad
    return high > low ? low...high : low...(low + 1)
}

struct StationTemperatureChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let unit = SettingService.shared.temperatureUnit
        let symbol = unit.symbol
        let lines = [
            StationChart.Line(points: points(history) { $0.dew_point_c.map(unit.value(fromCelsius:)) }, color: .mint, width: 1.5,
                              label: String(localized: "Taupunkt")),
            StationChart.Line(points: points(history) { $0.temperature_c.map(unit.value(fromCelsius:)) }, color: .orange,
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

struct StationWindChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let units = SettingService.shared.units
        let unit = units.wind.symbol
        let wind = { (metersPerSecond: Double) in units.windValue(metersPerSecond * 3.6) }
        let lines = [
            StationChart.Line(points: points(history) { $0.wind_gust_ms.map(wind) }, color: .teal.mix(with: .black, by: 0.4),
                              width: 1.5, label: String(localized: "Böen")),
            StationChart.Line(points: points(history) { $0.wind_speed_ms.map(wind) }, color: .teal,
                              label: String(localized: "Wind")),
        ]
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

struct StationPrecipitationChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame
    let total: Double?

    var body: some View {
        let units = SettingService.shared.units
        let unit = units.precipitation
        let bars = hourlyBars(unit)
        let peak = max(bars.map(\.value).max() ?? 0, unit.value(fromMillimeters: 1))
        StationChartCard(title: "Niederschlag", summary: String(localized: "\(units.precipitationString(total)) in 24h")) {
            StationChart(
                frame: frame, lines: [], bars: bars, yDomain: 0...(peak * 1.08),
                valueFormat: { "\($0.formatted(.number.precision(.fractionLength(unit.fractionDigits)))) \(unit.symbol)" })
        }
    }

    private func hourlyBars(_ unit: PrecipitationUnit) -> [StationChart.Bar] {
        var bars: [StationChart.Bar] = []
        for reading in history {
            guard let mm = reading.precipitation_mm else { continue }
            let value = unit.value(fromMillimeters: mm)
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

struct StationPressureChart: View {
    let history: [Components.Schemas.StationReading]
    let frame: StationChartFrame

    var body: some View {
        let unit = SettingService.shared.pressureUnit
        let lines = [StationChart.Line(points: points(history) { $0.pressure_hpa.map(unit.value(fromHectopascals:)) },
                                       color: .purple, label: String(localized: "Luftdruck"))]
        if !lines[0].points.isEmpty {
            StationChartCard(title: "Luftdruck", summary: threeHourTrend(lines[0].points, unit: unit)) {
                StationChart(
                    frame: frame, lines: lines, yDomain: paddedDomain(lines, minimumPad: unit.value(fromHectopascals: 2)),
                    valueFormat: { "\($0.formatted(.number.grouping(.never).precision(.fractionLength(unit.fractionDigits + 1)))) \(unit.symbol)" },
                    extremeFormat: { $0.formatted(.number.grouping(.never).precision(.fractionLength(unit.fractionDigits))) },
                    showsExtremes: true)
            }
        }
    }

    private func threeHourTrend(_ pressures: [StationChart.Point], unit: PressureUnit) -> String? {
        guard let last = pressures.last else { return nil }
        let target = last.time.addingTimeInterval(-3 * 3600)
        guard let earlier = pressures.min(by: { abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target)) }),
              abs(earlier.time.timeIntervalSince(target)) <= 1800 else { return nil }
        let delta = (last.value - earlier.value).formatted(
            .number.precision(.fractionLength(unit.fractionDigits + 1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(delta) \(unit.symbol) in 3h")
    }
}

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
    let lines: [Line]
    var bars: [Bar] = []
    let yDomain: ClosedRange<Double>
    let valueFormat: (Double) -> String
    var extremeFormat: ((Double) -> String)?
    var showsExtremes = false
    var arrows: [Point] = []

    @State private var selectedDate: Date?

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
            AxisMarks(values: tickDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self), frame.window.upperBound.timeIntervalSince(date) >= 3.5 * 3600 {
                        Text(HourlyChartUtilities.hourString(from: date, timeZone: frame.timeZone))
                    }
                }
                AxisGridLine()
                AxisTick()
            }
        }
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
        HourlyChartUtilities.daySeparatorMarks(time: hourStamps, timeZone: frame.timeZone)
    }

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

    private var runs: [(id: String, line: Line, points: [Point])] {
        lines.enumerated().flatMap { index, line in
            Self.segments(line.points).enumerated().map { segment, points in ("\(index)-\(segment)", line, points) }
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(runs, id: \.id) { run in
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

    private func tooltip(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: SettingService.formattedTime(date, timeZone: frame.timeZone))
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
        let calendar = HourlyChartUtilities.calendar(in: frame.timeZone)
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: frame.window.lowerBound)
        components.hour = ((components.hour ?? 0) / 6) * 6
        guard let first = calendar.date(from: components) else { return [] }
        return stride(from: 0, through: 30, by: 6).compactMap { calendar.date(byAdding: .hour, value: $0, to: first) }
            .filter { frame.window.contains($0) }
    }

    private var hourStamps: [Double] {
        Array(stride(from: frame.window.lowerBound.timeIntervalSince1970, through: frame.window.upperBound.timeIntervalSince1970, by: 3600))
    }

    private var accessibilitySummary: String {
        lines.reversed().compactMap { line in
            line.points.last.map { "\(line.label) \(valueFormat($0.value))" }
        }.joined(separator: ", ")
    }

    private func extremes(of line: Line) -> [(point: Point, isHigh: Bool)] {
        guard let high = line.points.max(by: { $0.value < $1.value }),
              let low = line.points.min(by: { $0.value < $1.value }),
              high.value - low.value >= (yDomain.upperBound - yDomain.lowerBound) / 4 else { return [] }
        return [(high, true), (low, false)]
    }

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
