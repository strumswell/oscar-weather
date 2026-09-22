//
//  RainRadarLiveActivityWidget.swift
//  Oscar°Widget
//

import ActivityKit
import SwiftUI
import WidgetKit

/// The rain card: Lock Screen banner, Dynamic Island and the watch Smart Stack.
/// The server ships timestamps and mm/h; every line of copy is written here at
/// render time, in the device's language and time format.
struct RainRadarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainRadarActivityAttributes.self) { context in
            let model = RainActivityModel(context: context)
            RainActivityCard(model: model)
                .background(RainActivityStyle.sky(for: model.phase))
                .activityBackgroundTint(RainActivityStyle.skyBottom(for: model.phase))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let model = RainActivityModel(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        RainActivityIcon(model: model)
                        Text(model.locationName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RainInlineValue(model: model)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.headline)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text(model.subline)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        RainTimelineChart(model: model, plotHeight: 28, compact: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RainActivityIcon(model: model)
            } compactTrailing: {
                RainActivityCompactTrailing(model: model)
            } minimal: {
                RainActivityIcon(model: model)
            }
            .widgetURL(RainActivityStyle.openURL)
            .keylineTint(model.tint)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Presentation model

private struct RainActivityModel {
    typealias ContentState = RainRadarActivityAttributes.ContentState
    typealias Bucket = ContentState.Bucket

    /// The one number the card leads with: the rain right now, or the peak still to come.
    struct Hero {
        let value: Double
        let label: LocalizedStringKey
        let bucketID: Int
    }

    let state: ContentState
    let locationName: String
    let isStale: Bool
    let now: Date

    init(context: ActivityViewContext<RainRadarActivityAttributes>) {
        self.init(state: context.state, locationName: context.attributes.locationName, isStale: context.isStale)
    }

    init(state: ContentState, locationName: String, isStale: Bool, now: Date = Date()) {
        self.state = state
        self.locationName = locationName
        self.isStale = isStale
        self.now = now
    }

    var phase: ContentState.Phase { state.phase }
    var buckets: [Bucket] { state.timeline }

    /// Earlier observations sit left of the "now" marker, greyed out; the newest one is "now".
    var pastCount: Int { buckets.filter { $0.t < state.observedAt }.count }

    var nowFraction: Double {
        buckets.isEmpty ? 0 : Double(pastCount) / Double(buckets.count)
    }

    var forecastBuckets: [Bucket] {
        buckets.filter { $0.t > state.observedAt }
    }

    /// The newest observed step: what the radar measures right now.
    var nowBucket: Bucket? { buckets.last { $0.t <= state.observedAt } }

    /// Heaviest step from now on.
    var peakAhead: Bucket? {
        let from = nowBucket?.t ?? state.observedAt
        return buckets.filter { $0.t >= from && $0.v > 0 }.max { $0.v < $1.v }
    }

    var hero: Hero? {
        guard !isStale else { return nil }
        switch phase {
        case .raining, .ending:
            if let bucket = nowBucket, bucket.v > 0 {
                return Hero(value: bucket.v, label: "jetzt", bucketID: bucket.id)
            }
            return peakAhead.map { Hero(value: $0.v, label: "max.", bucketID: $0.id) }
        case .upcoming:
            return peakAhead.map { Hero(value: $0.v, label: "max.", bucketID: $0.id) }
        case .ended:
            return nil
        }
    }

    /// The peak gets its number written on the bar when it's clearly heavier than the hero.
    var calloutBucket: Bucket? {
        guard !isStale, let peak = peakAhead, peak.id != hero?.bucketID,
              peak.v >= max(1, 1.5 * (hero?.value ?? 0)) else { return nil }
        return peak
    }

    var tint: Color {
        guard phase != .ended, let value = hero?.value ?? peakAhead?.v else {
            return .white.opacity(0.6)
        }
        return RainIntensity.color(value)
    }

    /// Axis label halfway between the marker and the horizon, as bar-centre fraction.
    var middleBucket: (fraction: Double, date: Date)? {
        guard buckets.count >= 8 else { return nil }
        let index = (pastCount + buckets.count - 1) / 2
        guard buckets.indices.contains(index) else { return nil }
        return ((Double(index) + 0.5) / Double(buckets.count), buckets[index].date)
    }

    var headline: String {
        switch phase {
        case .upcoming:
            if let start = state.startDate, start.timeIntervalSince(now) > -120 {
                return String(localized: "Regen ab \(time(start))")
            }
            return String(localized: "Regen in Kürze")
        case .raining:
            return String(localized: "Regnet gerade")
        case .ending:
            return String(localized: "Lässt bald nach")
        case .ended:
            return String(localized: "Regen vorbei")
        }
    }

    var subline: String {
        if phase == .ended {
            if let next = state.nextStartDate {
                return String(localized: "Neuer Regen gegen \(time(next))")
            }
            return String(localized: "Vorerst trocken")
        }
        if isStale {
            return String(localized: "Keine aktuellen Radardaten · Stand \(time(state.observedDate))")
        }
        guard let end = state.endDate else { return intensityLabel }
        return state.endIsOpen
            ? String(localized: "\(intensityLabel) · mindestens bis \(time(end))")
            : String(localized: "\(intensityLabel) · bis ca. \(time(end))")
    }

    /// Dynamic Island, compact: the one time that matters for the phase.
    var trailingStatus: String {
        switch phase {
        case .upcoming:
            return state.startDate.map(time) ?? ""
        case .raining, .ending:
            return state.endDate.map(time) ?? ""
        case .ended:
            return String(localized: "Vorbei")
        }
    }

    var radarStamp: String {
        String(localized: "Radar \(time(state.observedDate))")
    }

    /// Same thresholds as the server's push wording.
    var intensityLabel: String {
        let peak = state.peakMmPerHour
        if peak >= 24 { return String(localized: "Starker Regen") }
        if peak >= 6 { return String(localized: "Regen") }
        if peak >= 0.6 { return String(localized: "Leichter Regen") }
        return String(localized: "Nieselregen")
    }

    var accessibilityValue: String {
        [headline, subline, hero.map { "\(RainIntensity.format($0.value)) \(RainIntensity.unit)" }]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    func time(_ date: Date) -> String {
        SettingService.formattedTime(date)
    }
}

/// Bars share the radar map's palette and a fixed scale, so a bar means the same
/// amount of rain on every update and matches the colour the user saw on the map.
private enum RainIntensity {
    /// A full-height bar: heavy rain and above.
    static let ceiling = 20.0

    static var isInch: Bool { SettingService.resolvedPrecipitationUnit == "inch" }
    static var unit: String { isInch ? "in/h" : "mm/h" }

    /// Scale lines in mm/h, on round numbers of the display unit.
    static var gridlines: [Double] { isInch ? [1.27, 5.08] : [1, 5] }

    /// Logarithmic, bending at 0.1 mm/h, so the everyday 0.1–1 mm/h drizzle still
    /// gets distinct heights.
    static func fraction(_ mmPerHour: Double) -> Double {
        guard mmPerHour > 0 else { return 0 }
        let knee = 0.1
        return min(1, log1p(mmPerHour / knee) / log1p(ceiling / knee))
    }

    static func format(_ mmPerHour: Double) -> String {
        if isInch {
            return (mmPerHour / 25.4).formatted(.number.precision(.fractionLength(2)))
        }
        return mmPerHour.formatted(.number.precision(.fractionLength(mmPerHour < 10 ? 1 : 0)))
    }

    static func scaleLabel(_ mmPerHour: Double) -> String {
        let value = isInch ? mmPerHour / 25.4 : mmPerHour
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The map's plasma colour for a rain rate (Marshall–Palmer back to dBZ).
    static func color(_ mmPerHour: Double) -> Color {
        let stops = ServerColormapStops.radar
        let dbz: Double = 10 * log10(200 * pow(max(mmPerHour, 0.01), 1.6))
        guard let upper = stops.firstIndex(where: { $0.dbz >= dbz }) else {
            return Color(hex: stops[stops.count - 1].hex)
        }
        guard upper > 0 else { return Color(hex: stops[0].hex) }
        let low = stops[upper - 1], high = stops[upper]
        let progress: Double = (dbz - low.dbz) / (high.dbz - low.dbz)
        return Color(hex: low.hex).mix(with: Color(hex: high.hex), by: progress)
    }
}

private enum RainActivityStyle {
    /// Oscar's sky, darkened for the Lock Screen: brooding before the rain, deep
    /// while it falls, lifting once it's over. White text stays legible on any wallpaper.
    static func sky(for phase: RainRadarActivityAttributes.ContentState.Phase) -> LinearGradient {
        LinearGradient(colors: [skyTop(for: phase), skyBottom(for: phase)], startPoint: .top, endPoint: .bottom)
    }

    static func skyTop(for phase: RainRadarActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .upcoming: Color(hue: 0.64, saturation: 0.32, brightness: 0.36)
        case .raining, .ending: Color(hue: 0.60, saturation: 0.58, brightness: 0.36)
        case .ended: Color(hue: 0.58, saturation: 0.50, brightness: 0.48)
        }
    }

    static func skyBottom(for phase: RainRadarActivityAttributes.ContentState.Phase) -> Color {
        switch phase {
        case .upcoming: Color(hue: 0.66, saturation: 0.55, brightness: 0.14)
        case .raining, .ending: Color(hue: 0.64, saturation: 0.78, brightness: 0.14)
        case .ended: Color(hue: 0.62, saturation: 0.62, brightness: 0.20)
        }
    }

    static let dry = Color.white.opacity(0.2)
    static let past = Color.white.opacity(0.28)
    static let openURL = URL(string: "oscar://radar")
}

// MARK: - Lock Screen and watch

private struct RainActivityCard: View {
    let model: RainActivityModel
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            RainActivitySmallCard(model: model)
        } else {
            RainActivityFullCard(model: model)
        }
    }
}

private struct RainActivityFullCard: View {
    let model: RainActivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        RainActivityIcon(model: model)
                        Text(model.locationName)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(model.radarStamp)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    Text(model.headline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 2)
                    Text(model.subline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if let hero = model.hero {
                    RainHeroValue(hero: hero)
                }
            }
            if !model.buckets.isEmpty {
                RainTimelineChart(model: model, plotHeight: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

/// watchOS Smart Stack: two lines and the bars, no chrome.
private struct RainActivitySmallCard: View {
    let model: RainActivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.headline)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                RainInlineValue(model: model, showsUnit: false)
            }
            Text(model.subline)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !model.buckets.isEmpty {
                RainTimelineChart(model: model, plotHeight: 16, compact: true, detailed: false, showsAxis: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Big number like the temperature on the Wetter tab, with a legend dot in the bar colour.
private struct RainHeroValue: View {
    let hero: RainActivityModel.Hero

    var body: some View {
        VStack(alignment: .trailing, spacing: -2) {
            Text(RainIntensity.format(hero.value))
                .font(.system(size: 40, weight: .regular))
                .monospacedDigit()
                .contentTransition(.numericText(value: hero.value))
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                Circle()
                    .fill(RainIntensity.color(hero.value))
                    .frame(width: 6, height: 6)
                Text(verbatim: RainIntensity.unit)
                Text(hero.label)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .fixedSize()
    }
}

/// The hero on one line, for the Dynamic Island and the watch.
private struct RainInlineValue: View {
    let model: RainActivityModel
    var showsUnit = true

    var body: some View {
        if let hero = model.hero {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(RainIntensity.format(hero.value))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(RainIntensity.color(hero.value))
                if showsUnit {
                    Text(verbatim: RainIntensity.unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .fixedSize()
        } else {
            Text(model.trailingStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Timeline

/// Capsule bars on a fixed rain scale, coloured like the radar map: earlier
/// observations greyed out left of a "now" marker, the nowcast to the right, the peak labelled,
/// mm/h lines on the trailing edge and clock times underneath.
private struct RainTimelineChart: View {
    let model: RainActivityModel
    let plotHeight: CGFloat
    var compact = false
    /// Scale lines and the peak label.
    var detailed = true
    var showsAxis = true

    private var scaleWidth: CGFloat { RainIntensity.isInch ? 24 : 12 }
    private static let calloutHeight: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 5) {
                bars
                    .background(alignment: .bottom) { if detailed { gridlines } }
                    .overlay(alignment: .bottomLeading) { nowMarker }
                if detailed {
                    scaleLabels
                }
            }
            .padding(.top, headroom)
            if showsAxis {
                axis
                    .padding(.trailing, detailed ? scaleWidth + 5 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Regenverlauf"))
        .accessibilityValue(Text(verbatim: model.accessibilityValue))
    }

    /// Room above the plot when the labelled peak bar is nearly full height.
    private var headroom: CGFloat {
        guard detailed, let peak = model.calloutBucket else { return 0 }
        return max(0, barHeight(peak.v) + Self.calloutHeight - plotHeight)
    }

    private func barHeight(_ value: Double) -> CGFloat {
        guard value > 0 else { return 3 }
        return max(5, CGFloat(RainIntensity.fraction(value)) * plotHeight)
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: compact ? 2 : 3) {
            ForEach(model.buckets) { bucket in
                Capsule(style: .continuous)
                    .fill(fill(for: bucket))
                    .frame(height: barHeight(bucket.v))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        if detailed, bucket.id == model.calloutBucket?.id {
                            Text(RainIntensity.format(bucket.v))
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .fixedSize()
                                .offset(y: -(barHeight(bucket.v) + 3))
                        }
                    }
            }
        }
        .frame(height: plotHeight, alignment: .bottom)
        .saturation(model.isStale ? 0 : 1)
        .opacity(model.isStale ? 0.6 : 1)
    }

    private func fill(for bucket: RainActivityModel.Bucket) -> Color {
        if bucket.v <= 0 { return RainActivityStyle.dry }
        return bucket.t < model.state.observedAt ? RainActivityStyle.past : RainIntensity.color(bucket.v)
    }

    private var gridlines: some View {
        ZStack(alignment: .bottom) {
            ForEach(RainIntensity.gridlines, id: \.self) { value in
                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(height: 0.5)
                    .offset(y: -plotHeight * RainIntensity.fraction(value))
            }
        }
        .frame(height: plotHeight, alignment: .bottom)
    }

    private var scaleLabels: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(RainIntensity.gridlines, id: \.self) { value in
                Text(RainIntensity.scaleLabel(value))
                    .offset(y: -plotHeight * RainIntensity.fraction(value) + 6)
            }
        }
        .font(.system(size: 9, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.5))
        .frame(width: scaleWidth, height: plotHeight, alignment: .bottomLeading)
    }

    private var nowMarker: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.white.opacity(0.6))
                .frame(width: 1, height: plotHeight + 3)
                .offset(x: proxy.size.width * model.nowFraction - 0.5, y: -3)
        }
    }

    private var axis: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Text("Jetzt")
                    .fixedSize()
                    .offset(x: min(width * model.nowFraction + 3, max(0, width - 40)))
                if let middle = model.middleBucket {
                    Text(model.time(middle.date))
                        .fixedSize()
                        .position(x: width * middle.fraction, y: 6)
                }
                if let last = model.buckets.last {
                    HStack {
                        Spacer(minLength: 0)
                        Text(model.time(last.date))
                            .fixedSize()
                    }
                }
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
        .frame(height: 12)
    }
}

// MARK: - Dynamic Island pieces

private struct RainActivityCompactTrailing: View {
    let model: RainActivityModel

    var body: some View {
        switch model.phase {
        case .upcoming:
            Text(model.trailingStatus)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        case .raining, .ending:
            // While it rains the question is "how much longer": the next 40 minutes as bars.
            RainSparkline(buckets: Array(model.forecastBuckets.prefix(8)))
                .frame(width: 30, height: 12)
        case .ended:
            Text(model.trailingStatus)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct RainSparkline: View {
    let buckets: [RainRadarActivityAttributes.ContentState.Bucket]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(buckets) { bucket in
                Capsule(style: .continuous)
                    .fill(bucket.v > 0 ? RainIntensity.color(bucket.v) : RainActivityStyle.dry)
                    .frame(width: 2.5, height: bucket.v > 0 ? 3 + 9 * RainIntensity.fraction(bucket.v) : 2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct RainActivityIcon: View {
    let model: RainActivityModel

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(model.tint)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch model.phase {
        case .upcoming: "cloud.rain"
        case .raining: "cloud.rain.fill"
        case .ending: "cloud.drizzle.fill"
        case .ended: "cloud"
        }
    }
}

// MARK: - Previews

// Plain view previews on purpose: the Live Activity preview macro needs a preview
// host running the whole widget bundle inside the app and keeps timing out here.
// The debug menu on the Wetter tab starts real sample cards on a device.

private func previewModel(_ phase: RainRadarActivityAttributes.ContentState.Phase, stale: Bool = false) -> RainActivityModel {
    RainActivityModel(state: .sample(phase: phase), locationName: "Leipzig", isStale: stale)
}

#Preview("Sperrbildschirm") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach([RainRadarActivityAttributes.ContentState.Phase.upcoming, .raining, .ending, .ended], id: \.self) { phase in
                RainActivityFullCard(model: previewModel(phase))
                    .background(RainActivityStyle.sky(for: phase), in: .rect(cornerRadius: 24))
            }
            RainActivityFullCard(model: previewModel(.raining, stale: true))
                .background(RainActivityStyle.sky(for: .raining), in: .rect(cornerRadius: 24))
        }
        .frame(width: 366)
        .padding()
    }
    .background(.black)
}

#Preview("Watch") {
    VStack(spacing: 12) {
        ForEach([RainRadarActivityAttributes.ContentState.Phase.upcoming, .raining], id: \.self) { phase in
            RainActivitySmallCard(model: previewModel(phase))
                .frame(width: 184)
                .background(RainActivityStyle.sky(for: phase), in: .rect(cornerRadius: 18))
        }
    }
    .padding()
    .background(.black)
}

#Preview("Dynamic Island") {
    VStack(spacing: 20) {
        ForEach([RainRadarActivityAttributes.ContentState.Phase.upcoming, .raining, .ended], id: \.self) { phase in
            let model = previewModel(phase)
            HStack(spacing: 8) {
                RainActivityIcon(model: model)
                Spacer().frame(width: 90)
                RainActivityCompactTrailing(model: model)
            }
            .padding(.horizontal, 12)
            .frame(height: 37)
            .background(.black, in: .capsule)
            .overlay { Capsule().stroke(.white.opacity(0.2)) }
        }
        VStack(alignment: .leading, spacing: 6) {
            let model = previewModel(.raining)
            HStack {
                RainActivityIcon(model: model)
                Text(model.locationName).font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
                RainInlineValue(model: model)
            }
            Text(model.headline).font(.headline).foregroundStyle(.white)
            Text(model.subline).font(.caption).foregroundStyle(.white.opacity(0.65))
            RainTimelineChart(model: model, plotHeight: 28, compact: true)
        }
        .padding(16)
        .frame(width: 366)
        .background(.black, in: .rect(cornerRadius: 44))
        .overlay { RoundedRectangle(cornerRadius: 44).stroke(.white.opacity(0.2)) }
    }
    .padding()
    .background(Color(white: 0.15))
}
