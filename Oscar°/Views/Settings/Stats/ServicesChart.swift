import SwiftUI

struct ServicesChart: View {
    let calls: [String: Int]

    private struct Provider: Identifiable {
        let id: String
        let name: LocalizedStringKey
        var rows: [(key: String, count: Int)]
        var total: Int { rows.reduce(0) { $0 + $1.count } }
    }

    var body: some View {
        let providers = Self.providers(calls)
        let busiest = calls.values.max() ?? 1

        VStack(alignment: .leading, spacing: 18) {
            ForEach(providers) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(provider.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(provider.total, format: .number)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ForEach(provider.rows, id: \.key) { row in
                        StatsBarRow(title: Self.title(row.key), count: row.count, most: busiest, tint: .blue)
                    }
                }
            }
            Text("Jede einzelne Netzwerkanfrage zählt. Karten laden viele kleine Kacheln, deshalb steigen diese Werte schnell.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private static func providers(_ calls: [String: Int]) -> [Provider] {
        var providers: [String: Provider] = [:]
        for (key, count) in calls {
            let host = key.split(separator: "/").first.map(String.init) ?? key
            let (id, name): (String, LocalizedStringKey) =
                if host.hasSuffix("open-meteo.com") { ("open-meteo", "Open-Meteo") }
                else if host.hasSuffix("oscars.love") { ("oscar", "Oscar Server") }
                else if host.contains("weather.gc.ca") { ("canada", "Environment Canada") }
                else { (host, LocalizedStringKey(host)) }
            providers[id, default: Provider(id: id, name: name, rows: [])].rows.append((key, count))
        }
        return providers.values
            .map { provider in
                var sorted = provider
                sorted.rows.sort { $0.count > $1.count }
                return sorted
            }
            .sorted { $0.total > $1.total }
    }

    private static func title(_ key: String) -> String {
        switch key {
        case "api.open-meteo.com": String(localized: "Vorhersage")
        case "air-quality-api.open-meteo.com": String(localized: "Luftqualität")
        case "geocoding-api.open-meteo.com": String(localized: "Ortssuche")
        case "archive-api.open-meteo.com": String(localized: "Klimaarchiv")
        case let key where key.hasSuffix("/radar"): String(localized: "Regenradar")
        case let key where key.hasSuffix("/clouds"): String(localized: "Wolken")
        case let key where key.hasSuffix("/layers"): String(localized: "Kartenebenen")
        case let key where key.hasSuffix("/alerts"): String(localized: "Warnungen")
        case let key where key.hasSuffix("/stations"): String(localized: "Messstationen")
        case let key where key.hasSuffix("/webcams"): String(localized: "Webcams")
        case let key where key.hasSuffix("/notifications"): String(localized: "Mitteilungen")
        case let key where key.hasSuffix("oscars.love"): String(localized: "Ohne Aufschlüsselung")
        case let key where key.contains("weather.gc.ca"): String(localized: "Warnungen")
        default: String(localized: "Sonstiges")
        }
    }
}
