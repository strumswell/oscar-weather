//
//  RainRadarLiveActivityWidget.swift
//  Oscar°Widget
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RainRadarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainRadarActivityAttributes.self) { context in
            RainRadarLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RainRadarLiveActivityIcon(phase: context.state.displayPhase(isStale: context.isStale))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.primaryText(isStale: context.isStale))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RainRadarTimelineView(buckets: context.state.timeline, compact: true)
                }
            } compactLeading: {
                RainRadarLiveActivityIcon(phase: context.state.displayPhase(isStale: context.isStale))
            } compactTrailing: {
                Text(context.state.compactText(isStale: context.isStale))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                RainRadarLiveActivityIcon(phase: context.state.displayPhase(isStale: context.isStale))
            }
            .widgetURL(URL(string: "oscar://rain-radar"))
        }
    }
}

private struct RainRadarLiveActivityLockScreenView: View {
    let context: ActivityViewContext<RainRadarActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.primaryText(isStale: context.isStale))
                        .font(.title3.weight(.semibold))
                    Text(context.state.secondaryText(isStale: context.isStale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                RainRadarLiveActivityIcon(phase: context.state.displayPhase(isStale: context.isStale))
                    .font(.title2)
            }

            RainRadarTimelineView(buckets: context.state.timeline, compact: false)
                .opacity(context.isStale ? 0.45 : 1)

            Text(context.state.footerText(isStale: context.isStale))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .widgetURL(URL(string: "oscar://rain-radar"))
    }
}

private struct RainRadarTimelineView: View {
    let buckets: [RainRadarActivityAttributes.ContentState.TimelineBucket]
    let compact: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: compact ? 3 : 5) {
            ForEach(buckets.prefix(compact ? 8 : 10)) { bucket in
                Capsule()
                    .fill(bucket.isWet ? Color.cyan : Color.white.opacity(0.28))
                    .frame(width: compact ? 5 : 8, height: height(for: bucket))
                    .accessibilityLabel(Text(bucket.isWet ? "Regen" : "Trocken"))
            }
        }
        .frame(height: compact ? 28 : 42, alignment: .bottom)
    }

    private func height(for bucket: RainRadarActivityAttributes.ContentState.TimelineBucket) -> CGFloat {
        let value = min(max(Double(bucket.precipitation), 0), 250)
        let base = compact ? 6.0 : 8.0
        let range = compact ? 20.0 : 32.0
        return base + range * (value / 250.0)
    }
}

private struct RainRadarLiveActivityIcon: View {
    let phase: RainRadarActivityAttributes.ContentState.Phase

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch phase {
        case .upcoming:
            return "cloud.rain"
        case .raining:
            return "cloud.heavyrain"
        case .endingSoon:
            return "cloud.sun.rain"
        case .ended:
            return "cloud"
        case .stale:
            return "arrow.clockwise"
        }
    }

    private var color: Color {
        switch phase {
        case .stale:
            return .secondary
        case .ended:
            return .white.opacity(0.75)
        default:
            return .cyan
        }
    }
}

private extension RainRadarActivityAttributes.ContentState {
    func displayPhase(isStale: Bool) -> Phase {
        isStale ? .stale : phase
    }

    func primaryText(isStale: Bool) -> String {
        if isStale { return String(localized: "Radar wird aktualisiert") }
        switch phase {
        case .upcoming:
            if let minutesUntilStart {
                return String(localized: "Regen in \(minutesUntilStart) min")
            }
            return String(localized: "Regen in Kürze")
        case .raining:
            return String(localized: "Regnet gerade")
        case .endingSoon:
            return String(localized: "Endet bald")
        case .ended:
            return String(localized: "Regen vorbei")
        case .stale:
            return String(localized: "Radar wird aktualisiert")
        }
    }

    func compactText(isStale: Bool) -> String {
        if isStale { return "..." }
        if let minutesUntilStart, phase == .upcoming { return "\(minutesUntilStart)m" }
        if let minutesUntilEnd { return "\(minutesUntilEnd)m" }
        return phase == .raining ? String(localized: "Jetzt") : ""
    }

    func secondaryText(isStale: Bool) -> String {
        if isStale {
            return String(localized: "Warte auf aktuelle Radardaten")
        }
        if let minutesUntilEnd, phase == .raining || phase == .endingSoon {
            return isEndOpenEnded
                ? String(localized: "\(intensityLabel), noch mindestens \(minutesUntilEnd) min")
                : String(localized: "\(intensityLabel), noch \(minutesUntilEnd) min")
        }
        return intensityLabel
    }

    func footerText(isStale: Bool) -> String {
        let date = SettingService.formattedTime(lastObservedDate)
        if isStale {
            return String(localized: "Letztes Radarbild \(date)")
        }
        return String(localized: "\(locationName) · Aktualisiert \(date)")
    }

    private var lastObservedDate: Date {
        PrecipSeriesDate.parse(lastObservedAt) ?? Date()
    }
}
