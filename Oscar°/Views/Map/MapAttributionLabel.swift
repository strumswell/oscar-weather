import SwiftUI

struct MapAttributionLabel: View {
    @State private var visible = true

    var body: some View {
        Text(verbatim: "© OpenMapTiles © OpenStreetMap")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .shadow(color: .black.opacity(0.4), radius: 1)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.8)) {
                    visible = false
                }
            }
    }
}
