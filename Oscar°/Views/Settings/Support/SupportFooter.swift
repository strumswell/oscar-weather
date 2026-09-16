import StoreKit
import SwiftUI

struct SupportFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ein Teil von allem, was hier zusammenkommt, geht an Projekte gegen die Klimakrise.")
            Text("Abos verlängern sich automatisch, bis du sie in den Einstellungen deiner Apple-ID kündigst.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { links }
                VStack(alignment: .leading, spacing: 10) { links }
            }
            .padding(.top, 4)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    @ViewBuilder private var links: some View {
        Button("Käufe wiederherstellen", action: restorePurchases)
        Link("Datenschutz", destination: URL(string: "https://oscars.love/privacy")!)
        Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
    }

    private func restorePurchases() {
        Task { try? await AppStore.sync() }
    }
}
