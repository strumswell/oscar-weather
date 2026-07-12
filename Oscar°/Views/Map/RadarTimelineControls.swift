import SwiftUI
import Observation
import UIKit

// MARK: - Shared player-state surface

/// The slice of OscarRadarState / ModelGridLayerState that the unified timeline
/// chip drives. Both are @MainActor @Observable classes; property reads through
/// the existential still register with SwiftUI's observation tracking.
@MainActor
protocol TimelinePlayerState: AnyObject, Observable {
    var frameTimestamps: [String] { get }
    var currentFrameIndex: Int { get set }
    var isPlaying: Bool { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var loadedFrameIndices: Set<Int> { get }
    var loadingFrameIndices: Set<Int> { get }
    var hasAnyLoadedFrame: Bool { get }
    func play()
    func pause()
    func beginScrubbing()
    func endScrubbing()
}

extension OscarRadarState: TimelinePlayerState {}
extension ModelGridLayerState: TimelinePlayerState {}

// MARK: - Shared timeline helpers

/// Index of the frame closest to the wall clock (the scrubber's "now" marker).
private func closestIndexToNow(_ timestamps: [String]) -> Int? {
    guard !timestamps.isEmpty else { return nil }
    return closestTimestampIndex(in: timestamps.map(parseFrameDate))
}

private enum TimelineFormatters {
    /// Compact signed offsets for the status pill / axis end ("+35 Min.", "+2 Std.").
    nonisolated(unsafe) static let delta: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        return f
    }()
    nonisolated(unsafe) static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
}

// MARK: - Layer-specific wrappers

struct OscarRadarTimelineControls: View {
    let radarState: OscarRadarState
    /// Tapping the source badge (e.g. "DWD Radar") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: radarState,
            sourceLabel: sourceLabel,
            shortSourceLabel: shortSourceLabel,
            isLive: radarState.isCurrentFrameLive,
            loadingLabel: "Oscar Radar-Daten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }

    private var sourceLabel: String {
        switch radarState.region {
        case .germany: "DWD Radar"
        case .europe: "OPERA Radar"
        case .usa: "NOAA Radar"
        case .taiwan: "CWA Radar"
        }
    }

    private var shortSourceLabel: String {
        switch radarState.region {
        case .germany: "DWD"
        case .europe: "OPERA"
        case .usa: "NOAA"
        case .taiwan: "CWA"
        }
    }
}

struct WeatherTileTimelineControls: View {
    let imageState: ModelGridLayerState
    /// Tapping the source badge (e.g. "DWD ICON-D2") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: imageState,
            sourceLabel: imageState.currentLayer?.sourceLabel ?? "",
            shortSourceLabel: shortSourceLabel,
            isLive: false,
            loadingLabel: "Wetterdaten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }

    private var shortSourceLabel: String {
        switch imageState.currentLayer {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: "ICON-D2"
        case .gfsPrecip, .gfsTemp, .gfsWind, .gfsPressure: "GFS"
        case nil: ""
        }
    }
}

// MARK: - Unified timeline chip

/// One-row header (play + time + status pill + source) over the scrubber.
/// Loading is communicated as playability, video-player style: a buffered band
/// grows along the track, the play button carries a progress ring, and the
/// unbuffered remainder shimmers. Before metadata arrives the chip renders a
/// same-size skeleton so nothing jumps when data lands.
struct TimelineControlsChip: View {
    let state: any TimelinePlayerState
    let sourceLabel: String
    let shortSourceLabel: String
    let isLive: Bool
    let loadingLabel: LocalizedStringKey
    var onBadgeTap: (() -> Void)?

    /// Latches once the initial prefetch is over so the progress ring doesn't
    /// flicker back in when playback or the residency window reloads single
    /// evicted frames (which briefly re-populates loadingFrameIndices).
    @State private var prefetchSettled = false

    var body: some View {
        VStack(spacing: 10) {
            header

            let frameCount = state.frameTimestamps.count
            if frameCount > 1 {
                TimelineScrubber(
                    timestamps: state.frameTimestamps,
                    selectedIndex: state.currentFrameIndex,
                    loadedIndices: state.loadedFrameIndices,
                    onSelectionChanged: { index in
                        guard index != state.currentFrameIndex else { return }
                        state.currentFrameIndex = index
                        UIApplication.shared.playHapticFeedback()
                    },
                    onInteractionChanged: { isInteracting in
                        if isInteracting {
                            state.beginScrubbing()
                        } else {
                            state.endScrubbing()
                        }
                    }
                )
            } else if frameCount == 0 {
                GhostTrack()
                    .accessibilityLabel(Text(loadingLabel))
            }

            if let error = state.error {
                errorFooter(error)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
        // Block the underlying map from receiving touches inside the chip
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
        .onChange(of: bufferFraction >= 1) { _, full in
            if full { prefetchSettled = true }
        }
        .onChange(of: state.frameTimestamps) { _, _ in
            prefetchSettled = false
        }
        .task(id: loadingIsIdle) {
            // Idle without ever reaching 100 % (failed frames, eviction on very
            // long timelines): settle after a debounce instead of never.
            guard loadingIsIdle else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            prefetchSettled = true
        }
    }

    private var loadingIsIdle: Bool {
        !state.isLoading && state.loadingFrameIndices.isEmpty && state.hasAnyLoadedFrame
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            playButton
            // Fixed-content variants so ViewThatFits can drop the weekday and
            // shorten the source label before anything truncates.
            ViewThatFits(in: .horizontal) {
                headerContent(showDay: true, source: sourceLabel)
                headerContent(showDay: false, source: sourceLabel)
                headerContent(showDay: false, source: shortSourceLabel)
            }
        }
    }

    private func headerContent(showDay: Bool, source: String) -> some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(selectedTime)
                    .font(.headline.monospacedDigit())
                if showDay, !selectedDay.isEmpty {
                    Text(selectedDay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: 6)
            statusPill
            sourceBadge(source)
        }
    }

    private var playButton: some View {
        Button {
            if state.isPlaying { state.pause() } else { state.play() }
            UIApplication.shared.playHapticFeedback()
        } label: {
            ZStack {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .glassEffect(in: Circle())
                if showsBufferRing {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 2.5)
                        .frame(width: 37, height: 37)
                    Circle()
                        .trim(from: 0, to: bufferFraction)
                        .stroke(.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 37, height: 37)
                }
            }
            .animation(.smooth(duration: 0.35), value: bufferFraction)
            .animation(.smooth(duration: 0.35), value: showsBufferRing)
        }
        .buttonStyle(.plain)
        .disabled(state.frameTimestamps.isEmpty)
        .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Wiedergabe"))
    }

    /// Fraction of the timeline that is decoded and ready — the play button's
    /// determinate progress ring during prefetch.
    private var bufferFraction: CGFloat {
        let count = state.frameTimestamps.count
        guard count > 0 else { return 0 }
        return CGFloat(state.loadedFrameIndices.count) / CGFloat(count)
    }

    private var showsBufferRing: Bool {
        !prefetchSettled && bufferFraction < 1
    }

    // MARK: Status pill

    /// LIVE on the natural now frame, "Jetzt" when a coarser timeline sits on
    /// its closest-to-now frame, otherwise a signed offset that jumps back to now.
    @ViewBuilder
    private var statusPill: some View {
        if isLive {
            HStack(spacing: 5) {
                PulsingDot()
                Text("LIVE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(in: Capsule())
        } else if let date = selectedDate {
            if state.currentFrameIndex == closestIndexToNow(state.frameTimestamps) {
                Text("Jetzt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(in: Capsule())
            } else {
                let delta = date.timeIntervalSinceNow
                Button(action: jumpToNow) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.bold))
                        Text(deltaLabel(delta))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(delta > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Zur aktuellen Zeit springen"))
            }
        }
    }

    private func deltaLabel(_ delta: TimeInterval) -> String {
        let formatted = TimelineFormatters.delta.string(from: abs(delta)) ?? ""
        return (delta > 0 ? "+" : "−") + formatted
    }

    private func jumpToNow() {
        guard let index = closestIndexToNow(state.frameTimestamps),
              index != state.currentFrameIndex else { return }
        state.currentFrameIndex = index
        UIApplication.shared.playHapticFeedback()
    }

    // MARK: Source badge

    @ViewBuilder
    private func sourceBadge(_ title: String) -> some View {
        if !title.isEmpty {
            Button(action: { onBadgeTap?() }) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onBadgeTap == nil)
            .accessibilityHint(Text("Öffnet die Kartenebenen"))
        }
    }

    // MARK: Error footer

    private func errorFooter(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Selected frame

    private var selectedTimestamp: String? {
        let stamps = state.frameTimestamps
        guard stamps.indices.contains(state.currentFrameIndex) else { return nil }
        return stamps[state.currentFrameIndex]
    }

    private var selectedDate: Date? {
        selectedTimestamp.flatMap(parseFrameDate)
    }

    private var selectedTime: String {
        guard let date = selectedDate else { return "--:--" }
        return SettingService.formattedTime(date)
    }

    private var selectedDay: String {
        guard let date = selectedDate else { return "" }
        return TimelineFormatters.weekday.string(from: date)
    }
}

// MARK: - Scrubber

private struct TimelineScrubber: View {
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

// MARK: - Loading choreography pieces

/// One slow highlight sweeping the track — "working" without per-frame flicker.
/// Callers mask it to the unbuffered gaps (or show it bare on the skeleton).
private struct ShimmerBand: View {
    let trackWidth: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let period: TimeInterval = 2.8
            let phase = CGFloat(
                context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period)
            let bandWidth: CGFloat = 72
            Color.clear
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.18), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: bandWidth)
                        .offset(x: phase * (trackWidth + bandWidth) - bandWidth)
                }
                .clipShape(Capsule())
        }
        .frame(width: trackWidth, height: height)
        .allowsHitTesting(false)
    }
}

/// Rounded rects over the given x-ranges — the shimmer's gap mask.
private struct SegmentsShape: Shape {
    let segments: [ClosedRange<CGFloat>]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in segments {
            let width = segment.upperBound - segment.lowerBound
            guard width > 0.5 else { continue }
            path.addRoundedRect(
                in: CGRect(x: segment.lowerBound, y: rect.minY,
                           width: width, height: rect.height),
                cornerSize: CGSize(width: rect.height / 2, height: rect.height / 2))
        }
        return path
    }
}

/// Indeterminate ring around the thumb while the frame under it is decoding.
private struct ThumbLoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 25, height: 25)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .shadow(color: .black.opacity(0.25), radius: 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}

/// Skeleton track shown before frame metadata arrives — same footprint as the
/// real scrubber so the chip doesn't jump when data lands.
private struct GhostTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 10)
                    if !reduceMotion {
                        ShimmerBand(trackWidth: proxy.size.width, height: 10)
                    }
                }
                .frame(height: 26)
                HStack {
                    Text(verbatim: "--:--")
                    Spacer()
                    Text(verbatim: "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(height: 14)
            }
        }
        .frame(height: 46)
    }
}

// MARK: - Timestamp badge (map preview)
// isLive is driven explicitly by OscarRadarState.isCurrentFrameLive so that the
// pulsing dot only appears on the "natural now" frame, never on scrubbed frames.

struct RadarTimestampBadge: View {
    let timestamp: String
    var isLive: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if isLive {
                PulsingDot()
                Text("LIVE")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text(formattedTime)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(in: Capsule())
    }

    private var formattedTime: String {
        guard let date = parseFrameDate(timestamp) else { return "--:--" }
        return SettingService.formattedTime(date)
    }
}

// MARK: - Pulsing dot

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.5 : 1.0)
            .opacity(pulsing ? 0.5 : 1.0)
            .onAppear { pulsing = !reduceMotion }
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
    }
}
