import SwiftUI

struct StatsView: View {
    private let store = UsageStatsStore.shared
    private let settings = SettingService.shared

    var body: some View {
        let stats = store.combined
        ScrollView {
            VStack(spacing: 16) {
                StatsOverviewGrid(stats: stats)

                StatsCard(title: "Deine Aktivität") {
                    ActivityHeatmap(stats: stats)
                }

                StatsCard(title: "Wann du Oscar öffnest") {
                    OpensByHourChart(counts: stats.opensByHour)
                    Divider()
                    OpensByWeekdayChart(counts: stats.opensByWeekday)
                }

                if !stats.places.isEmpty {
                    StatsCard(title: "Deine Orte") {
                        TopPlacesChart(places: stats.places)
                    }
                }

                StatsCard(title: "Extremwerte") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ExtremeTile(title: "Heißester Moment", extreme: stats.hottest?.converted(to: temperatureUnit), tint: .orange)
                        ExtremeTile(title: "Kältester Moment", extreme: stats.coldest?.converted(to: temperatureUnit), tint: .cyan)
                        ExtremeTile(title: "Stärkster Wind", extreme: stats.windiest?.converted(to: windUnit), tint: .mint)
                        ExtremeTile(title: "Stärkster Regen", extreme: stats.wettest?.converted(to: precipitationUnit), tint: .blue)
                        ExtremeTile(title: "Höchster UV-Index", extreme: stats.highestUV, tint: .yellow)
                    }
                }

                if let cat = stats.cat {
                    CatStatsCard(counts: cat)
                }

                StatsCard(title: "Unterwegs in Oscar") {
                    VStack(spacing: 10) {
                        StatsRow(title: "Gescrollt", value: Text(Measurement(value: stats.scrolledMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))))
                        StatsRow(title: "Längste Sitzung", value: Text(Duration.seconds(stats.longestSessionSeconds), format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
                        StatsRow(title: "Mitteilungen gesehen", value: Text(stats.notificationsShown, format: .number))
                        StatsRow(title: "Mitteilungen geöffnet", value: Text(stats.notificationsOpened, format: .number))
                        ForEach(stats.sheets.sorted { $0.value > $1.value }, id: \.key) { sheet, count in
                            StatsRow(title: Self.sheetTitle(sheet), value: Text(count, format: .number))
                        }
                    }
                }

                if !stats.apiCalls.isEmpty {
                    StatsCard(title: "Anfragen an Wetterdienste") {
                        ServicesChart(calls: stats.apiCalls)
                    }
                }

                Group {
                    if store.otherInstalls.isEmpty {
                        Text("Alle Zahlen bleiben auf deinem Gerät und in deiner iCloud.")
                    } else {
                        Text("Zusammengezählt über \(store.otherInstalls.count + 1) Geräte. Alle Zahlen bleiben auf deinen Geräten und in deiner iCloud.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Statistik")
        .toolbarTitleDisplayMode(.inline)
        .onAppear { store.flush() }
    }

    private var temperatureUnit: String {
        settings.temperatureUnit.symbol
    }

    private var windUnit: String {
        switch settings.windSpeedUnit {
        case .kmh, .bft: "km/h"
        case .ms: "m/s"
        case .mph: "mph"
        case .kn: "kn"
        }
    }

    private var precipitationUnit: String {
        settings.precipitationUnit == .inch ? "in" : "mm"
    }

    private static func sheetTitle(_ id: String) -> LocalizedStringKey {
        switch id {
        case "hourly": "Stundenansicht geöffnet"
        case "daily": "Tagesansicht geöffnet"
        case "climate": "Klima geöffnet"
        case "stations": "Messstationen geöffnet"
        case "alerts": "Warnungen geöffnet"
        case "settings": "Einstellungen geöffnet"
        case "layout": "Ansicht angepasst"
        case "support": "Oscar unterstützen"
        case let id where id.hasPrefix("environment"): "Umwelt geöffnet"
        default: LocalizedStringKey(id)
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
