import SwiftUI

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

struct PulsingDot: View {
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
