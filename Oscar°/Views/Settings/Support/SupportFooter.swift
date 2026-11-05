import StoreKit
import SwiftUI

struct SupportFooter: View {
    @State private var managesSubscriptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Einen Teil meines Gewinns aus Oscar werde ich an ausgewählte gemeinnützige Organisationen spenden und das öffentlich bekannt geben.")
            Text("Abos verlängern sich automatisch, wenn du sie nicht spätestens 24 Stunden vor Ende des Zeitraums in den Einstellungen deiner Apple-ID kündigst.")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { links }
                VStack(alignment: .leading, spacing: 10) { links }
            }
            .padding(.top, 4)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .manageSubscriptionsSheet(isPresented: $managesSubscriptions)
    }

    @ViewBuilder private var links: some View {
        Button("Abo verwalten") { managesSubscriptions = true }
        Button("Käufe wiederherstellen", action: restorePurchases)
        Link("Datenschutz", destination: LegalPage.privacy)
        Link("Nutzungsbedingungen", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
    }

    private func restorePurchases() {
        Task { try? await AppStore.sync() }
    }
}
