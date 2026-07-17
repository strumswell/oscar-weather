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
            AlertListView()
        case .settings:
            SettingsView()
        }
    }
}
