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
            RainActivityCard(model: RainActivityModel(context: context))
                .activityBackgroundTint(RainActivityStyle.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let model = RainActivityModel(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        RainActivityIcon(phase: model.phase)
                        Text(model.locationName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(model.trailingStatus)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.headline)
                            .font(.headline)
                            .foregroundStyle(.white)
                        RainTimelineChart(model: model, barHeight: 22, compact: true)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                RainActivityIcon(phase: model.phase)
            } compactTrailing: {
                RainActivityCompactTrailing(model: model)
            } minimal: {
                RainActivityIcon(phase: model.phase)
            }
            .widgetURL(RainActivityStyle.openURL)
            .keylineTint(RainActivityStyle.accent)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Presentation model

private struct RainActivityModel {
    typealias ContentState = RainRadarActivityAttributes.ContentState

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
    var buckets: [ContentState.Bucket] { state.timeline }

    /// Observed steps sit left of the "now" marker, dimmed.
    var pastCount: Int { buckets.filter { $0.t <= state.observedAt }.count }

    var nowFraction: Double {
        buckets.isEmpty ? 0 : Double(pastCount) / Double(buckets.count)
    }

    var forecastBuckets: [ContentState.Bucket] {
        buckets.filter { $0.t > state.observedAt }
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

    /// Dynamic Island, expanded: the one time that matters for the phase.
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

    func time(_ date: Date) -> String {
        SettingService.formattedTime(date)
    }
}

private enum RainActivityStyle {
    /// Deep night-sky navy: the card reads the same on every wallpaper and white
    /// text stays legible, like the app's dark canvas.
    static let background = Color(red: 0.07, green: 0.11, blue: 0.23).opacity(0.92)
    static let accent = Color.cyan
    static let wet = LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom)
    static let dry = Color.white.opacity(0.22)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RainActivityIcon(phase: model.phase)
                    .font(.caption)
                Text(model.locationName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(model.radarStamp)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(model.subline)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if !model.buckets.isEmpty {
                RainTimelineChart(model: model, barHeight: 34, compact: false)
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
            Text(model.headline)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(model.subline)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if !model.buckets.isEmpty {
                RainTimelineChart(model: model, barHeight: 16, compact: true, showsAxis: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Timeline

/// Capsule bars like the lock-screen rain widget and the watch: observed steps
/// dimmed left of a "now" marker, the nowcast to the right, clock times underneath.
private struct RainTimelineChart: View {
    let model: RainActivityModel
    let barHeight: CGFloat
    let compact: Bool
    var showsAxis = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            bars.overlay(alignment: .bottomLeading) { nowMarker }
            if showsAxis {
                axis
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Regenverlauf"))
    }

    private var bars: some View {
        let reference = RainNowcastSummary.reference(for: model.buckets.map(\.v))
        return HStack(alignment: .bottom, spacing: compact ? 2 : 3) {
            ForEach(model.buckets) { bucket in
                Capsule(style: .continuous)
                    .fill(bucket.v > 0 ? AnyShapeStyle(RainActivityStyle.wet) : AnyShapeStyle(RainActivityStyle.dry))
                    .frame(height: height(for: bucket.v, reference: reference))
                    .frame(maxWidth: .infinity)
                    .opacity(bucket.t <= model.state.observedAt ? 0.45 : 1)
            }
        }
        .frame(height: barHeight, alignment: .bottom)
        .opacity(model.isStale ? 0.5 : 1)
    }

    private func height(for value: Double, reference: Double) -> CGFloat {
        guard value > 0 else { return 3 }
        let fraction = RainNowcastSummary.barFraction(value: value, reference: reference)
        return 4 + CGFloat(fraction) * (barHeight - 4)
    }

    private var nowMarker: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.white.opacity(0.55))
                .frame(width: 1, height: barHeight + 3)
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
        let reference = RainNowcastSummary.reference(for: buckets.map(\.v))
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(buckets) { bucket in
                Capsule(style: .continuous)
                    .fill(bucket.v > 0 ? AnyShapeStyle(RainActivityStyle.wet) : AnyShapeStyle(RainActivityStyle.dry))
                    .frame(width: 2.5, height: height(for: bucket.v, reference: reference))
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func height(for value: Double, reference: Double) -> CGFloat {
        guard value > 0 else { return 2 }
        return 3 + 9 * CGFloat(RainNowcastSummary.barFraction(value: value, reference: reference))
    }
}

private struct RainActivityIcon: View {
    let phase: RainRadarActivityAttributes.ContentState.Phase

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(phase == .ended ? Color.white.opacity(0.6) : RainActivityStyle.accent)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch phase {
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
                    .background(RainActivityStyle.background, in: .rect(cornerRadius: 24))
            }
            RainActivityFullCard(model: previewModel(.raining, stale: true))
                .background(RainActivityStyle.background, in: .rect(cornerRadius: 24))
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
                .background(RainActivityStyle.background, in: .rect(cornerRadius: 18))
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
                RainActivityIcon(phase: model.phase)
                Spacer().frame(width: 90)
                RainActivityCompactTrailing(model: model)
            }
            .padding(.horizontal, 12)
            .frame(height: 37)
            .background(.black, in: .capsule)
            .overlay(Capsule().stroke(.white.opacity(0.2)))
        }
        VStack(alignment: .leading, spacing: 6) {
            let model = previewModel(.raining)
            HStack {
                RainActivityIcon(phase: model.phase)
                Text(model.locationName).font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(model.trailingStatus).font(.caption.weight(.semibold)).foregroundStyle(.white)
            }
            Text(model.headline).font(.headline).foregroundStyle(.white)
            RainTimelineChart(model: model, barHeight: 22, compact: true)
        }
        .padding(16)
        .frame(width: 366)
        .background(.black, in: .rect(cornerRadius: 44))
        .overlay(RoundedRectangle(cornerRadius: 44).stroke(.white.opacity(0.2)))
    }
    .padding()
    .background(Color(white: 0.15))
}
