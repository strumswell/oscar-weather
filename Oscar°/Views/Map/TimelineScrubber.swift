import SwiftUI
import UIKit

// MARK: - Scrubber

struct TimelineScrubber: View {
    let timestamps: [String]
    let selectedIndex: Int
    let loadedIndices: Set<Int>
    let onSelectionChanged: (Int) -> Void
    let onInteractionChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    /// Raw finger x while dragging — the thumb follows this continuously instead
    /// of snapping between quantized frame positions, so scrubbing tracks at
    /// display refresh rate. nil when idle (thumb sits on the selected frame).
    @State private var dragX: CGFloat?
    /// timestamps parsed once per timeline — body re-runs per drag pixel and
    /// must not re-parse 50 ISO strings each time.
    @State private var cachedDates: [Date?] = []

    private var frameCount: Int { timestamps.count }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackWidth = max(width - thumbDiameter, 1)
            let dates = cachedDates.count == timestamps.count
                ? cachedDates
                : timestamps.map(parseFrameDate)
            let nowIndex = closestTimestampIndex(in: dates)
            let runs = loadedRuns()
            let nowCenter = thumbRadius + xOffset(for: nowIndex, width: trackWidth)
            let nowLabelX = min(max(nowCenter - nowLabelWidth / 2, 0), width - nowLabelWidth)
            // All collision tests use measured label widths (see labelWidth):
            // the edge labels can be wide ("12:55 PM"), mid marks are usually
            // short ("2 PM", "14:00") — hardcoded slot constants either waste
            // marks or overlap, depending on locale.
            let startWidth = labelWidth(edgeLabel(dates.first ?? nil))
            let endWidth = labelWidth(edgeLabel(dates.last ?? nil))
            let showStart = nowLabelX > startWidth + 8
            let showEnd = nowLabelX + nowLabelWidth < width - endWidth - 8
            let midMarks = midAxisLabels(dates: dates, trackWidth: trackWidth).filter { mark in
                abs(mark.x - nowCenter) > (nowLabelWidth + mark.width) / 2 + 4
                    && mark.x - mark.width / 2 > (showStart ? startWidth + 6 : 8)
                    && mark.x + mark.width / 2 < width - (showEnd ? endWidth + 6 : 8)
            }

            VStack(spacing: 6) {
                trackZone(width: width, trackWidth: trackWidth, dates: dates,
                          nowIndex: nowIndex, runs: runs, midMarks: midMarks)
                axisRow(width: width, dates: dates, midMarks: midMarks,
                        nowLabelX: nowLabelX, showStart: showStart, showEnd: showEnd)
            }
        }
        .frame(height: trackZoneHeight + 6 + axisHeight)
        .onChange(of: timestamps, initial: true) { _, stamps in
            cachedDates = stamps.map(parseFrameDate)
        }
    }

    // MARK: Track

    private func trackZone(width: CGFloat, trackWidth: CGFloat, dates: [Date?],
                           nowIndex: Int, runs: [ClosedRange<Int>],
                           midMarks: [(x: CGFloat, text: String, width: CGFloat)]) -> some View {
        let thumbOffset = dragX.map { min(max($0 - thumbRadius, 0), trackWidth) }
            ?? xOffset(for: selectedIndex, width: trackWidth)
        let selectionIsLoaded = loadedIndices.contains(selectedIndex)
        let fullyBuffered = loadedIndices.count >= frameCount

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.08))
                .frame(height: trackHeight)
                .padding(.horizontal, thumbRadius)

            // Buffered bands — playability, video-player style. Edges spring as
            // the contiguous ranges grow; islands from scrub-triggered preloads
            // render as their own segments.
            ZStack(alignment: .leading) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    Capsule()
                        .fill(.white.opacity(0.26))
                        .frame(width: bandWidth(for: run, trackWidth: trackWidth),
                               height: trackHeight)
                        .offset(x: xOffset(for: run.lowerBound, width: trackWidth))
                }
            }
            .padding(.leading, thumbRadius)
            .animation(.smooth(duration: 0.55), value: loadedIndices)

            // Nowcast/forecast zone right of the now marker.
            if nowIndex < frameCount - 1 {
                let nowX = xOffset(for: nowIndex, width: trackWidth)
                UnevenRoundedRectangle(bottomTrailingRadius: trackHeight / 2,
                                       topTrailingRadius: trackHeight / 2)
                    .fill(.orange.opacity(0.14))
                    .frame(width: max(trackWidth - nowX, 0), height: trackHeight)
                    .offset(x: thumbRadius + nowX)
            }

            Capsule()
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
                .frame(height: trackHeight)
                .padding(.horizontal, thumbRadius)

            // One tick per axis label, so the labels visibly anchor to the track.
            ForEach(midMarks, id: \.x) { mark in
                Capsule()
                    .fill(.white.opacity(0.32))
                    .frame(width: 1.5, height: 5)
                    .offset(x: mark.x - 0.75)
            }

            if !fullyBuffered && !reduceMotion {
                ShimmerBand(trackWidth: trackWidth, height: trackHeight)
                    .mask(SegmentsShape(segments: gapSegments(runs: runs, trackWidth: trackWidth)))
                    .frame(width: trackWidth, height: trackHeight)
                    .padding(.leading, thumbRadius)
            }

            // "Now" marker separating observation from nowcast.
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.9))
                .frame(width: 2, height: trackHeight + 6)
                .offset(x: thumbRadius + xOffset(for: nowIndex, width: trackWidth) - 1)
                .shadow(color: .black.opacity(0.3), radius: 1)

            Circle()
                .fill(.white.opacity(selectionIsLoaded ? 1 : 0.75))
                .frame(width: thumbDiameter, height: thumbDiameter)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                    if !selectionIsLoaded {
                        ThumbLoadingRing()
                    }
                }
                .offset(x: thumbOffset)
        }
        .frame(height: trackZoneHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onInteractionChanged(true)
                    }
                    dragX = value.location.x
                    onSelectionChanged(index(for: value.location.x, width: trackWidth))
                }
                .onEnded { value in
                    onSelectionChanged(index(for: value.location.x, width: trackWidth))
                    if isDragging {
                        isDragging = false
                        onInteractionChanged(false)
                    }
                    // Settle onto the selected frame's quantized position.
                    withAnimation(.snappy(duration: 0.2)) {
                        dragX = nil
                    }
                }
        )
        .onChange(of: fullyBuffered) { _, ready in
            // The whole timeline just became scrubbable under the user's finger.
            if ready && isDragging {
                UIApplication.shared.playHapticFeedback()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Zeitleiste")
        .accessibilityValue("\(selectedIndex + 1) von \(frameCount)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onSelectionChanged(min(frameCount - 1, selectedIndex + 1))
            case .decrement:
                onSelectionChanged(max(0, selectedIndex - 1))
            @unknown default:
                break
            }
        }
    }

    // MARK: Axis

    /// First and last frame time at the edges, round in-between times along the
    /// track, and "Jetzt" anchored under the now marker. Labels yield to their
    /// neighbors when space gets tight (filtering happens in body, shared with
    /// the track's tick marks).
    private func axisRow(width: CGFloat, dates: [Date?],
                         midMarks: [(x: CGFloat, text: String, width: CGFloat)],
                         nowLabelX: CGFloat, showStart: Bool, showEnd: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            HStack {
                if showStart {
                    Text(edgeLabel(dates.first ?? nil))
                }
                Spacer()
                if showEnd {
                    Text(edgeLabel(dates.last ?? nil))
                }
            }
            ForEach(midMarks, id: \.x) { label in
                Text(label.text)
                    .fixedSize()
                    .frame(width: label.width + 2)
                    .offset(x: label.x - (label.width + 2) / 2)
            }
            Text("Jetzt")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: nowLabelWidth)
                .offset(x: nowLabelX)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(height: axisHeight)
    }

    private func edgeLabel(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        return axisTime(date)
    }

    /// Axis time label. 12-hour locales get ":00" dropped on full hours
    /// ("2 PM" instead of "2:00 PM") — the AM/PM suffix already eats the
    /// width budget, and round track marks are full hours almost always.
    private func axisTime(_ date: Date) -> String {
        if uses12HourClock, Calendar.current.component(.minute, from: date) == 0 {
            return SettingService.formattedTime(date, showsMinutes: false)
        }
        return SettingService.formattedTime(date)
    }

    /// AM/PM designators are letters; 24-hour strings are digits and ":".
    private var uses12HourClock: Bool {
        SettingService.formattedTime(.now).contains(where: \.isLetter)
    }

    /// The axis row renders in .caption.monospacedDigit() — measure candidate
    /// labels with the matching UIFont so spacing decisions use real widths.
    private static let axisUIFont = UIFont.monospacedDigitSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)

    private func labelWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Self.axisUIFont]).width)
    }

    /// Round times between the first and last frame. Candidate steps go from
    /// dense to sparse; for each one the labels are generated and MEASURED,
    /// and the first step whose widest label (plus a 12 pt gap) fits the
    /// on-track spacing wins. Hour-only strings ("2 PM") therefore pack
    /// tighter than minute strings ("2:30 PM") automatically, in every
    /// locale, on every layer span — radar's 3 h and the models' 36 h alike.
    private func midAxisLabels(
        dates: [Date?], trackWidth: CGFloat
    ) -> [(x: CGFloat, text: String, width: CGFloat)] {
        guard let first = dates.first ?? nil, let last = dates.last ?? nil,
              last > first else { return [] }
        let span = last.timeIntervalSince(first)
        let steps: [TimeInterval] = [15, 30, 60, 120, 180, 360, 720, 1440].map { $0 * 60 }
        for step in steps {
            let spacing = CGFloat(step / span) * trackWidth
            var marks: [(x: CGFloat, text: String, width: CGFloat)] = []
            var widest: CGFloat = 0
            var tick = (first.timeIntervalSince1970 / step).rounded(.up) * step
            while tick < last.timeIntervalSince1970 - 1 {
                let text = axisTime(Date(timeIntervalSince1970: tick))
                widest = max(widest, labelWidth(text))
                let fraction = CGFloat((tick - first.timeIntervalSince1970) / span)
                marks.append((x: thumbRadius + fraction * trackWidth, text: text, width: 0))
                tick += step
            }
            if spacing >= widest + 12 {
                return marks.map { (x: $0.x, text: $0.text, width: widest) }
            }
        }
        return []
    }

    // MARK: Geometry & segments

    private var thumbDiameter: CGFloat { 18 }
    private var thumbRadius: CGFloat { thumbDiameter / 2 }
    private var trackHeight: CGFloat { 10 }
    private var trackZoneHeight: CGFloat { 26 }
    private var axisHeight: CGFloat { 14 }
    private var nowLabelWidth: CGFloat { 48 }

    /// Contiguous runs of loaded frames, left to right.
    private func loadedRuns() -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var index = 0
        while index < frameCount {
            if loadedIndices.contains(index) {
                var end = index
                while end + 1 < frameCount, loadedIndices.contains(end + 1) {
                    end += 1
                }
                runs.append(index...end)
                index = end + 1
            } else {
                index += 1
            }
        }
        return runs
    }

    /// X-ranges not covered by any buffered band — the shimmer's mask.
    private func gapSegments(runs: [ClosedRange<Int>], trackWidth: CGFloat) -> [ClosedRange<CGFloat>] {
        var gaps: [ClosedRange<CGFloat>] = []
        var cursor = 0
        for run in runs {
            if run.lowerBound > cursor {
                let from = xOffset(for: max(cursor - 1, 0), width: trackWidth)
                let to = xOffset(for: run.lowerBound, width: trackWidth)
                if to > from { gaps.append(from...to) }
            }
            cursor = run.upperBound + 1
        }
        if cursor < frameCount {
            let from = xOffset(for: max(cursor - 1, 0), width: trackWidth)
            if trackWidth > from { gaps.append(from...trackWidth) }
        }
        return gaps
    }

    private func bandWidth(for run: ClosedRange<Int>, trackWidth: CGFloat) -> CGFloat {
        let lower = xOffset(for: run.lowerBound, width: trackWidth)
        let upper = xOffset(for: run.upperBound, width: trackWidth)
        return max(upper - lower, 6)
    }

    private func index(for locationX: CGFloat, width: CGFloat) -> Int {
        guard frameCount > 1 else { return 0 }
        let clampedX = min(max(locationX - thumbRadius, 0), width)
        let fraction = clampedX / width
        return Int((fraction * CGFloat(frameCount - 1)).rounded())
    }

    private func xOffset(for index: Int, width: CGFloat) -> CGFloat {
        guard frameCount > 1 else { return 0 }
        let clampedIndex = max(0, min(frameCount - 1, index))
        let fraction = CGFloat(clampedIndex) / CGFloat(frameCount - 1)
        return fraction * width
    }
}
