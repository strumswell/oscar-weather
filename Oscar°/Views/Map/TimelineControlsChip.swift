import SwiftUI
import UIKit

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
