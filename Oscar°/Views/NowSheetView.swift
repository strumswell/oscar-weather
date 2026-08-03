import SwiftUI

struct NowSheetView: View {
    let sheet: NowSheet

    var body: some View {
        switch sheet {
        case .hourly:
            HourlyDetailView()
        case .daily:
            DailyDetailView()
        case .environment(let section):
            EnvironmentDetailView(scrollTo: section)
        case .climate(let summary):
            ClimateDetailView(summary: summary)
        case .alerts:
            // Matches the map's polygon tap sheet; no .presentationBackground
            // override — an explicit background would kill the glass.
            AlertListView()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.hidden)
        case .settings:
            SettingsView()
        }
    }
}
