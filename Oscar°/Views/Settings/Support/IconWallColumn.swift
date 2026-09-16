import SwiftUI

/// Loops its content downward: laid out `copies` times, one linear
/// repeat-forever offset advances by exactly one copy so the seam never shows.
struct IconWallColumn<Content: View>: View {
    let speed: Double
    var initialOffset = 0.0
    var copies = 5
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stackHeight = 0.0
    @State private var rolling = false

    private let spacing = 12.0

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<copies, id: \.self) { _ in
                VStack(spacing: spacing) { content }
            }
        }
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.height
        } action: { total in
            stackHeight = total
        }
        .offset(y: initialOffset - copyStride + (rolling ? copyStride : 0))
        .onChange(of: stackHeight) { restart() }
    }

    private var copyStride: Double {
        (stackHeight + spacing) / Double(copies)
    }

    private func restart() {
        rolling = false
        guard stackHeight > 0, !reduceMotion else { return }
        withAnimation(.linear(duration: copyStride / speed).repeatForever(autoreverses: false)) {
            rolling = true
        }
    }
}
