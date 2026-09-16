import SwiftUI

/// The layout page as a sheet: the forecast page's way in once every
/// section is hidden.
struct NowLayoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NowLayoutSettingsView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}
