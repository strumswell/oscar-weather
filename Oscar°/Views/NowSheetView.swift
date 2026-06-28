import SwiftUI

struct NowSheetView: View {
    let sheet: NowSheet
    let settingsService: SettingService
    let locationTransition: Namespace.ID

    var body: some View {
        switch sheet {
        case .location:
            SearchCityView()
                .presentationDetents([.large])
                .navigationTransition(.zoom(sourceID: NowSheet.locationTransitionID, in: locationTransition))
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
        case .legal:
            LegalView()
        }
    }
}
