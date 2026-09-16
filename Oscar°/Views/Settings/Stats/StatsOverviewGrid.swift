import SwiftUI

struct StatsOverviewGrid: View {
    let stats: UsageStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Geöffnet", value: Text(stats.opens, format: .number))
            StatTile(title: "Zeit in Oscar", value: Text(Duration.seconds(stats.activeSeconds), format: .units(allowed: [.hours, .minutes], width: .narrow)))
            StatTile(title: "Aktive Tage", value: Text(stats.activeDays, format: .number))
            StatTile(title: "Dabei seit", value: Text(stats.firstLaunch, format: .dateTime.day().month().year()))
        }
    }
}
