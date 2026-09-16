import SwiftUI

struct ProviderRow: View {
    let provider: DataProvider

    var body: some View {
        Label {
            provider.nameText
        } icon: {
            Image(systemName: provider.systemImage)
        }
        .labelStyle(.settingsIcon(provider.tint))
    }
}
