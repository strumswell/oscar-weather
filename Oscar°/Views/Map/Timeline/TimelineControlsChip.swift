import SwiftUI
import UIKit

// MARK: - Unified timeline chip

struct TimelineControlsChip: View {
    let state: any TimelinePlayerState
    let sourceLabel: String
    let shortSourceLabel: String
    let isLive: Bool
    let isForecast: Bool
    var forecastStartIndex: Int? = nil
    let loadingLabel: LocalizedStringKey
    var onBadgeTap: (() -> Void)?

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
                    isForecast: isForecast,
                    forecastStartIndex: forecastStartIndex,
                    onSelectionChanged: { index in
                        guard index != state.currentFrameIndex else { return }
                        state.currentFrameIndex = index
                        Haptics.impact()
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
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
        .onChange(of: bufferFraction >= 1) { _, full in
            if full { prefetchSettled = true }
        }
        .onChange(of: state.frameTimestamps) { _, _ in
            prefetchSettled = false
        }
        .task(id: loadingIsIdle) {
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
        } label: {
            ZStack {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.bold))
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

    private var bufferFraction: CGFloat {
        let count = state.frameTimestamps.count
        guard count > 0 else { return 0 }
        return CGFloat(state.loadedFrameIndices.count) / CGFloat(count)
    }

    private var showsBufferRing: Bool {
        !prefetchSettled && bufferFraction < 1
    }

    // MARK: Status pill

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
                let label = deltaLabel(delta)
                Button(action: jumpToNow) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.bold))
                        Text(label)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(delta > 0 && !isForecast && !isModelFrame
                                     ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .glassEffect(in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Zur aktuellen Zeit springen"))
            }
        }
    }

    private var isModelFrame: Bool {
        forecastStartIndex.map { state.currentFrameIndex >= $0 } ?? false
    }

    private func deltaLabel(_ delta: TimeInterval) -> String {
        let formatted = TimelineFormatters.delta.string(from: abs(delta)) ?? ""
        return (delta > 0 ? "+" : "−") + formatted
    }

    private func jumpToNow() {
        guard let index = closestIndexToNow(state.frameTimestamps),
              index != state.currentFrameIndex else { return }
        state.currentFrameIndex = index
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
