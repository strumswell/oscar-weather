import SwiftUI

struct LocationsEmptyHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Noch keine Orte gespeichert.")
                .font(.headline)
            Text("Suche nach einem Ort oder wähle einen Punkt auf der Karte.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
