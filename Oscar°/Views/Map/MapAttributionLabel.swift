import SwiftUI

/// ODbL/OpenMapTiles credit for the OpenFreeMap basemap. Initially visible in
/// the map corner, then auto-fades after 5 s — one of the collapse mechanisms
/// the OSMF attribution guidelines explicitly sanction, provided the credit
/// stays findable afterwards (SettingsView's OpenStreetMap/OpenFreeMap entries).
/// MapLibre's ⓘ button stays hidden; this label replaces it.
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
