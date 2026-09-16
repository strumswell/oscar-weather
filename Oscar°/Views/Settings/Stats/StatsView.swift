import SwiftUI

struct StatsView: View {
    private let store = UsageStatsStore.shared

    var body: some View {
        let stats = store.combined
        List {
            Section {
                StatsOverviewGrid(stats: stats)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Wann du Oscar öffnest") {
                OpensByHourChart(counts: stats.opensByHour)
                OpensByWeekdayChart(counts: stats.opensByWeekday)
            }

            if !stats.places.isEmpty {
                Section("Deine Orte") {
                    TopPlacesChart(places: stats.places)
                }
            }

            Section("Extremwerte") {
                ExtremeRow(title: "Heißester Moment", extreme: stats.hottest, icon: "thermometer.sun.fill", tint: .orange)
                ExtremeRow(title: "Kältester Moment", extreme: stats.coldest, icon: "thermometer.snowflake", tint: .cyan)
                ExtremeRow(title: "Stärkster Wind", extreme: stats.windiest, icon: "wind", tint: .mint)
                ExtremeRow(title: "Stärkster Regen", extreme: stats.wettest, icon: "cloud.heavyrain.fill", tint: .blue)
                ExtremeRow(title: "Höchster UV-Index", extreme: stats.highestUV, icon: "sun.max.fill", tint: .yellow)
            }

            Section("Unterwegs in Oscar") {
                LabeledContent("Gescrollt") {
                    Text(Measurement(value: stats.scrolledMeters, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
                }
                LabeledContent("Längste Sitzung") {
                    Text(Duration.seconds(stats.longestSessionSeconds), format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow))
                }
                LabeledContent("Mitteilungen gesehen") { Text(stats.notificationsShown, format: .number) }
                LabeledContent("Mitteilungen geöffnet") { Text(stats.notificationsOpened, format: .number) }
                ForEach(stats.sheets.sorted { $0.value > $1.value }, id: \.key) { sheet, count in
                    LabeledContent(Self.sheetTitle(sheet)) { Text(count, format: .number) }
                }
            }

            if !stats.apiCalls.isEmpty {
                Section {
                    ForEach(stats.apiCalls.sorted { $0.value > $1.value }, id: \.key) { host, count in
                        LabeledContent(Self.serviceTitle(host)) { Text(count, format: .number) }
                    }
                } header: {
                    Text("Anfragen an Wetterdienste")
                } footer: {
                    if store.otherInstalls.isEmpty {
                        Text("Alle Zahlen bleiben auf deinem Gerät und in deiner iCloud.")
                    } else {
                        Text("Zusammengezählt über \(store.otherInstalls.count + 1) Geräte. Alle Zahlen bleiben auf deinen Geräten und in deiner iCloud.")
                    }
                }
            }
        }
        .navigationTitle("Statistik")
        .toolbarTitleDisplayMode(.inline)
        // Folds the scroll distance collected since the last save into the numbers shown.
        .onAppear { store.flush() }
    }

    private static func sheetTitle(_ id: String) -> LocalizedStringKey {
        switch id {
        case "hourly": "Stundenansicht geöffnet"
        case "daily": "Tagesansicht geöffnet"
        case "climate": "Klima geöffnet"
        case "alerts": "Warnungen geöffnet"
        case "settings": "Einstellungen geöffnet"
        case "layout": "Ansicht angepasst"
        case let id where id.hasPrefix("environment"): "Umwelt geöffnet"
        default: LocalizedStringKey(id)
        }
    }

    private static func serviceTitle(_ host: String) -> LocalizedStringKey {
        switch host {
        case "api.open-meteo.com": "Open-Meteo Vorhersage"
        case "air-quality-api.open-meteo.com": "Open-Meteo Luftqualität"
        case "geocoding-api.open-meteo.com": "Open-Meteo Ortssuche"
        case "archive-api.open-meteo.com": "Open-Meteo Klimaarchiv"
        case let host where host.contains("weather.gc.ca"): "Environment Canada"
        case let host where host.hasSuffix("oscars.love"): "Oscar Server"
        default: LocalizedStringKey(host)
        }
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
