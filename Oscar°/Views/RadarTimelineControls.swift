import SwiftUI
import UIKit

// MARK: - Oscar Radar Timeline Controls

struct OscarRadarTimelineControls: View {
    @Bindable var radarState: OscarRadarState

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
                Slider(
                    value: Binding(
                        get: { Double(radarState.currentFrameIndex) },
                        set: { newVal in
                            let idx = Int(newVal.rounded())
                            guard idx != radarState.currentFrameIndex else { return }
                            radarState.currentFrameIndex = idx
                            UIApplication.shared.playHapticFeedback()
                        }
                    ),
                    in: 0...Double(frameCount - 1),
                    step: 1
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

    private var firstTimestamp: String { shortTime(from: radarState.frameTimestamps.first) }
    private var lastTimestamp: String  { shortTime(from: radarState.frameTimestamps.last) }
    private var previousTimestamp: String { timeAt(index: 0) }
    private var midTimestamp1: String { timeAt(index: oneThirdIndex) }
    private var midTimestamp2: String { timeAt(index: twoThirdIndex) }
    private var nextTimestamp: String { timeAt(index: radarState.frameTimestamps.count - 1) }

    private var selectedDay: String { day(from: radarState.currentFrameTimestamp) }
    private var selectedTime: String { shortTime(from: radarState.currentFrameTimestamp) }

    private var dwdBadge: some View {
        Text("DWD")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            )
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
              let date = ISO8601DateFormatter.radarFormatter.date(from: timestamp)
        else { return "--:--" }
        return DateFormatter.shortTime.string(from: date)
    }

    private func day(from timestamp: String?) -> String {
        guard let timestamp,
              let date = ISO8601DateFormatter.radarFormatter.date(from: timestamp)
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
        guard let date = ISO8601DateFormatter.radarFormatter.date(from: timestamp) else { return "--:--" }
        return DateFormatter.shortTime.string(from: date)
    }
}

// MARK: - Pulsing dot

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.5 : 1.0)
            .opacity(pulsing ? 0.5 : 1.0)
            .onAppear { pulsing = true }
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: pulsing
            )
    }
}

// MARK: - Shared formatter singletons

extension ISO8601DateFormatter {
    static let radarFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f
    }()
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
}
