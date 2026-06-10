import SwiftUI

struct NowSheetView: View {
    let sheet: NowSheet
    let settingsService: SettingService
    let locationTransition: Namespace.ID

    var body: some View {
        switch sheet {
        case .location:
            if #available(iOS 18.0, *) {
                SearchCityView()
                    .presentationDetents([.large])
                    .navigationTransition(
                        .zoom(sourceID: NowSheet.locationTransitionID, in: locationTransition)
                    )
            } else {
                SearchCityView()
                    .presentationDetents([.large])
            }
        case .hourly:
            HourlyDetailView()
        case .daily:
            DailyDetailView()
        case .environment(let section):
            EnvironmentDetailView(scrollTo: section)
        case .alerts:
            AlertListView()
        case .legal:
            LegalView()
        case .map:
            MapDetailView(settingsService: settingsService)
        }
    }
}
