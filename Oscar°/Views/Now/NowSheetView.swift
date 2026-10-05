import SwiftUI

struct NowSheetView: View {
    let sheet: NowSheet

    @Environment(\.dismiss) private var dismiss

    // The chart pages get a page-sized sheet on iPad, the Duo's inner
    // display and Mac; iPhone sheets ignore the sizing.
    var body: some View {
        switch sheet {
        case .hourly(let target):
            HourlyDetailView(initialTarget: target)
                .presentationSizing(.page)
        case .ensemble:
            // Wide layouts open it straight from 12-Tage; on iPhone it's pushed
            // from the hourly sheet instead.
            NavigationStack {
                EnsembleView(initialDate: .now)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { dismiss() }
                        }
                    }
            }
            .preferredColorScheme(.dark)
            .presentationSizing(.page)
        case .environment(let section):
            EnvironmentDetailView(scrollTo: section)
                .presentationSizing(.page)
        case .climate(let summary):
            ClimateDetailView(summary: summary)
                .presentationSizing(.page)
        case .stations(let id):
            StationDetailView(initialID: id)
                .presentationSizing(.page)
        case .alerts:
            // Matches the map's polygon tap sheet; no .presentationBackground
            // override — an explicit background would kill the glass.
            AlertListView()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.hidden)
        case .settings:
            SettingsView()
        case .layout:
            NowLayoutSheet()
        }
    }
}
