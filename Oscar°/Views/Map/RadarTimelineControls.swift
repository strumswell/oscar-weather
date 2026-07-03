import SwiftUI
import UIKit

// MARK: - Oscar Radar Timeline Controls

struct OscarRadarTimelineControls: View {
    @Bindable var radarState: OscarRadarState
    /// Tapping the source badge (e.g. "DWD Radar") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        Group {
            if radarState.frameTimestamps.isEmpty {
                // Metadata not yet fetched — show loading chip
                loadingChip
            } else {
                playerChip
            }
        }

        if let error = radarState.error {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
        }
    }

    // MARK: - Player chip

    private var playerChip: some View {
        VStack(spacing: 10) {
            // Row 1: play button
            HStack {
                Button {
                    if radarState.isPlaying { radarState.pause() } else { radarState.play() }
                    UIApplication.shared.playHapticFeedback()
                } label: {
                    Image(systemName: radarState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .glassEffect(in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(selectedTime)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Spacer()
            }

            // Row 2: frame scrubber
            let frameCount = radarState.frames.count
            if frameCount > 1 {
                TimelineScrubber(
                    frameCount: frameCount,
                    selectedIndex: radarState.currentFrameIndex,
                    loadedIndices: radarState.loadedFrameIndices,
                    loadingIndices: radarState.loadingFrameIndices,
                    contiguousReadyRange: radarState.contiguousReadyRange,
                    onSelectionChanged: { index in
                        guard index != radarState.currentFrameIndex else { return }
                        radarState.currentFrameIndex = index
                        UIApplication.shared.playHapticFeedback()
                    },
                    onInteractionChanged: { isInteracting in
                        if isInteracting {
                            radarState.beginScrubbing()
                        } else {
                            radarState.endScrubbing()
                        }
                    }
                )
            }

            // Row 3: axis timestamps
            HStack {
                Text(previousTimestamp)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(midTimestamp1)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(midTimestamp2)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(nextTimestamp)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            dwdBadge
                .padding(.top, 17)
                .padding(.trailing, 17)
        }
        // Block the underlying map from receiving touches inside the chip
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
    }

    // MARK: - Loading chip

    private var loadingChip: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.75)
            Text("Oscar Radar-Daten werden geladen…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Helpers

    private var previousTimestamp: String { timeAt(index: 0) }
    private var midTimestamp1: String { timeAt(index: oneThirdIndex) }
    private var midTimestamp2: String { timeAt(index: twoThirdIndex) }
    private var nextTimestamp: String { timeAt(index: radarState.frameTimestamps.count - 1) }

    private var selectedDay: String { day(from: radarState.currentFrameTimestamp) }
    private var selectedTime: String { shortTime(from: radarState.currentFrameTimestamp) }

    private var regionBadgeTitle: String {
        switch radarState.region {
        case .germany: "DWD Radar"
        case .europe: "OPERA Radar"
        case .usa: "NOAA Radar"
        }
    }

    private var dwdBadge: some View {
        Button(action: { onBadgeTap?() }) {
            Text(regionBadgeTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(onBadgeTap == nil)
        .accessibilityHint(Text("Öffnet die Kartenebenen"))
    }

    private func timeAt(index: Int) -> String {
        guard index >= 0, index < radarState.frameTimestamps.count else { return "--:--" }
        return shortTime(from: radarState.frameTimestamps[index])
    }

    private var oneThirdIndex: Int {
        guard radarState.frameTimestamps.count > 1 else { return 0 }
        return max(0, min(radarState.frameTimestamps.count - 1, radarState.frameTimestamps.count / 3))
    }

    private var twoThirdIndex: Int {
        guard radarState.frameTimestamps.count > 1 else { return 0 }
        return max(0, min(radarState.frameTimestamps.count - 1, (radarState.frameTimestamps.count * 2) / 3))
    }

    private func shortTime(from timestamp: String?) -> String {
        guard let timestamp,
              let date = ISO8601DateFormatter.parseRadarDate(timestamp)
        else { return "--:--" }
        return SettingService.formattedTime(date)
    }

    private func day(from timestamp: String?) -> String {
        guard let timestamp,
              let date = ISO8601DateFormatter.parseRadarDate(timestamp)
        else { return "--" }
        return DateFormatter.shortDay.string(from: date)
    }
}


// MARK: - Timestamp badge (A + D)
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
        guard let date = ISO8601DateFormatter.parseRadarDate(timestamp) else { return "--:--" }
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

// MARK: - Shared formatter singletons

extension ISO8601DateFormatter {
    // Handles "2024-01-15T12:00:00+00:00" and "2024-01-15T12:00:00Z"
    nonisolated(unsafe) static let radarFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // Handles "2024-01-15T12:00:00.000Z" and similar with sub-second precision
    nonisolated(unsafe) private static let radarFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Tries fractional-seconds ISO8601, plain ISO8601, and Unix epoch (seconds).
    static func parseRadarDate(_ string: String) -> Date? {
        radarFormatterFractional.date(from: string)
            ?? radarFormatter.date(from: string)
            ?? Double(string).map { Date(timeIntervalSince1970: $0) }
    }
}

extension DateFormatter {
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - Tile Layer Timeline Controls (ICON-D2 / GFS)

struct WeatherTileTimelineControls: View {
    @Bindable var imageState: ModelGridLayerState
    /// Tapping the source badge (e.g. "DWD ICON-D2") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        Group {
            if imageState.frameTimestamps.isEmpty || (imageState.isLoading && !imageState.hasAnyLoadedFrame) {
                loadingChip
            } else {
                playerChip
            }
        }
        if let error = imageState.error {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
        }
    }

    // MARK: - Player chip

    private var playerChip: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    if imageState.isPlaying { imageState.pause() } else { imageState.play() }
                    UIApplication.shared.playHapticFeedback()
                } label: {
                    Image(systemName: imageState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .glassEffect(in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(selectedTime)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Spacer()
                if imageState.isLoading && !imageState.hasCurrentFrame && imageState.hasAnyLoadedFrame {
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }

            let frameCount = imageState.frames.count
            if frameCount > 1 {
                TimelineScrubber(
                    frameCount: frameCount,
                    selectedIndex: imageState.currentFrameIndex,
                    loadedIndices: imageState.loadedFrameIndices,
                    loadingIndices: imageState.loadingFrameIndices,
                    contiguousReadyRange: imageState.contiguousReadyRange,
                    onSelectionChanged: { index in
                        guard index != imageState.currentFrameIndex else { return }
                        imageState.currentFrameIndex = index
                        UIApplication.shared.playHapticFeedback()
                    },
                    onInteractionChanged: { isInteracting in
                        if isInteracting {
                            imageState.beginScrubbing()
                        } else {
                            imageState.endScrubbing()
                        }
                    }
                )
            }

            HStack {
                Text(timeAt(index: 0))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeAt(index: oneThirdIndex))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeAt(index: twoThirdIndex))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeAt(index: imageState.frameTimestamps.count - 1))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            sourceBadge
                .padding(.top, 17)
                .padding(.trailing, 17)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
    }

    // MARK: - Loading chip

    private var loadingChip: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.75)
            Text("Wetterdaten werden geladen…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Badge

    private var sourceBadge: some View {
        Button(action: { onBadgeTap?() }) {
            Text(imageState.currentLayer?.sourceLabel ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(onBadgeTap == nil)
        .accessibilityHint(Text("Öffnet die Kartenebenen"))
    }

    // MARK: - Helpers

    private var selectedDay: String  { dayFrom(imageState.currentFrameTimestamp) }
    private var selectedTime: String { timeFrom(imageState.currentFrameTimestamp) }

    private var oneThirdIndex: Int {
        guard imageState.frameTimestamps.count > 1 else { return 0 }
        return max(0, min(imageState.frameTimestamps.count - 1, imageState.frameTimestamps.count / 3))
    }
    private var twoThirdIndex: Int {
        guard imageState.frameTimestamps.count > 1 else { return 0 }
        return max(0, min(imageState.frameTimestamps.count - 1, (imageState.frameTimestamps.count * 2) / 3))
    }

    private func timeAt(index: Int) -> String {
        guard index >= 0, index < imageState.frameTimestamps.count else { return "--:--" }
        return timeFrom(imageState.frameTimestamps[index])
    }

    private func timeFrom(_ ts: String?) -> String {
        guard let ts, let date = ISO8601DateFormatter.parseRadarDate(ts) else { return "--:--" }
        return SettingService.formattedTime(date)
    }

    private func dayFrom(_ ts: String?) -> String {
        guard let ts, let date = ISO8601DateFormatter.parseRadarDate(ts) else { return "--" }
        return DateFormatter.shortDay.string(from: date)
    }
}

private struct TimelineScrubber: View {
    let frameCount: Int
    let selectedIndex: Int
    let loadedIndices: Set<Int>
    let loadingIndices: Set<Int>
    let contiguousReadyRange: ClosedRange<Int>?
    let onSelectionChanged: (Int) -> Void
    let onInteractionChanged: (Bool) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(proxy.size.width - thumbDiameter, 1)
            let thumbOffset = xOffset(for: selectedIndex, width: trackWidth)
            let selectionIsLoaded = loadedIndices.contains(selectedIndex)
            let selectionIsLoading = loadingIndices.contains(selectedIndex)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.1))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbRadius)

                readinessHighlight(
                    contiguousReadyRange: contiguousReadyRange,
                    width: trackWidth
                )
                .padding(.horizontal, thumbRadius)

                stepMarkers
                    .padding(.horizontal, thumbRadius)

                Capsule()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.75)
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbRadius)

                Circle()
                    .fill(thumbFill(isLoaded: selectionIsLoaded, isLoading: selectionIsLoading))
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
                    .offset(x: thumbOffset)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onInteractionChanged(true)
                        }
                        onSelectionChanged(index(for: value.location.x, width: trackWidth))
                    }
                    .onEnded { value in
                        onSelectionChanged(index(for: value.location.x, width: trackWidth))
                        if isDragging {
                            isDragging = false
                            onInteractionChanged(false)
                        }
                    }
            )
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
        .frame(height: 26)
    }

    private var thumbDiameter: CGFloat { 18 }
    private var thumbRadius: CGFloat { thumbDiameter / 2 }
    private var trackHeight: CGFloat { 10 }
    private var markerHeight: CGFloat { 5 }

    @ViewBuilder
    private var stepMarkers: some View {
        HStack(spacing: 0) {
            ForEach(0..<frameCount, id: \.self) { index in
                let isSelected = index == selectedIndex
                let isLoaded = loadedIndices.contains(index)
                let isLoading = loadingIndices.contains(index)

                Capsule()
                    .fill(markerColor(isSelected: isSelected, isLoaded: isLoaded, isLoading: isLoading))
                    .frame(width: markerWidth(isSelected: isSelected), height: markerHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: trackHeight)
    }

    private func markerColor(isSelected: Bool, isLoaded: Bool, isLoading: Bool) -> Color {
        if isSelected {
            return isLoaded ? .white.opacity(0.9) : .orange.opacity(0.9)
        }

        if isLoading {
            return .orange.opacity(0.6)
        }

        if isLoaded {
            return .white.opacity(0.36)
        }

        return .white.opacity(0.1)
    }

    private func markerWidth(isSelected: Bool) -> CGFloat {
        isSelected ? 5 : 2.5
    }

    @ViewBuilder
    private func readinessHighlight(
        contiguousReadyRange: ClosedRange<Int>?,
        width: CGFloat
    ) -> some View {
        if let contiguousReadyRange {
            let lower = min(max(contiguousReadyRange.lowerBound, 0), frameCount - 1)
            let upper = min(max(contiguousReadyRange.upperBound, 0), frameCount - 1)
            let lowerOffset = xOffset(for: lower, width: width)
            let upperOffset = xOffset(for: upper, width: width)
            readinessSegment(
                minX: lowerOffset,
                maxX: upperOffset
            )
            .frame(height: trackHeight)
        }
    }

    private func readinessSegment(
        minX: CGFloat,
        maxX: CGFloat
    ) -> some View {
        Capsule()
            .fill(.white.opacity(0.22))
            .frame(width: max(maxX - minX, 10), height: trackHeight)
            .offset(x: minX)
    }

    private func thumbFill(isLoaded: Bool, isLoading: Bool) -> some ShapeStyle {
        if isLoaded {
            return AnyShapeStyle(Color.white)
        }

        if isLoading {
            return AnyShapeStyle(Color.orange.opacity(0.94))
        }

        return AnyShapeStyle(Color.white.opacity(0.82))
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
