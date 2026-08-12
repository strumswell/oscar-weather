import SwiftUI

// MARK: - Loading choreography pieces

/// One slow highlight sweeping the track — "working" without per-frame flicker.
/// Callers mask it to the unbuffered gaps (or show it bare on the skeleton).
struct ShimmerBand: View {
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
struct SegmentsShape: Shape {
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
struct ThumbLoadingRing: View {
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
struct GhostTrack: View {
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
