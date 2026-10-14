import SwiftUI

struct NowLayoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NowLayoutSettingsView(resetPlacement: .topBarLeading)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}
