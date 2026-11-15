// Small home widget with air quality, UV and pollen or the pollutant driving the AQI.
import SwiftUI
import WidgetKit

struct AirRow: Identifiable {
    let label: String
    let status: String
    let value: Int
    let metric: EnvironmentMetric

    var id: String { label }
}

struct AirEntry: TimelineEntry {
    let date: Date
    let location: String
    let rows: [AirRow]
    var cityID: String? = nil
}

struct AirProvider: PlaceTimelineSource {
    typealias Payload = Operations.getAirQuality.Output.Ok.Body.jsonPayload

    let client = APIClient.shared
    let refreshMinutes = 180

    func placeholder(in context: Context) -> AirEntry {
        AirEntry(date: Date(), location: "Berlin", rows: [
            Self.aqiRow(label: String(localized: "Luft"), value: 32),
            Self.uvRow(1),
            Self.aqiRow(label: String(localized: "PM2,5"), value: 14),
        ].compactMap { $0 })
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [AirEntry] {
        let (air, _) = try await WidgetCache.fetch(WidgetCache.key("air", place.coordinates), maxAge: 600) {
            try await client.getAirQuality(coordinates: place.coordinates)
        }
        let location = await place.locationName()
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let dates = [now] + stride(from: 3600.0, to: Double(refreshMinutes) * 60, by: 3600).map { hour.addingTimeInterval($0) }
        return dates.map { date in
            AirEntry(date: date, location: location, rows: Self.rows(from: air, at: date), cityID: place.cityID)
        }
    }

    static func rows(from air: Payload, at date: Date) -> [AirRow] {
        let hourly = air.hourly
        let time = hourly?.time ?? []
        func value(_ values: [Double]?) -> Double? {
            environmentValue(from: values, time: time, now: date)
        }
        func pollen(_ values: [Double?]?) -> Double? {
            environmentValue(from: values, time: time, now: date) ?? nil
        }

        let worstPollen = worstPollenRow([
            (.alder, String(localized: "Erle"), pollen(hourly?.alder_pollen)),
            (.birch, String(localized: "Birke"), pollen(hourly?.birch_pollen)),
            (.grass, String(localized: "Gräser"), pollen(hourly?.grass_pollen)),
            (.mugwort, String(localized: "Beifuß"), pollen(hourly?.mugwort_pollen)),
            (.ragweed, String(localized: "Ambrosia"), pollen(hourly?.ragweed_pollen)),
        ])
        let worstPollutant = worstPollutantRow([
            (String(localized: "PM2,5"), value(hourly?.european_aqi_pm2_5)),
            ("PM10", value(hourly?.european_aqi_pm10)),
            ("NO₂", value(hourly?.european_aqi_no2)),
            ("O₃", value(hourly?.european_aqi_o3)),
        ])

        return [
            value(hourly?.european_aqi).flatMap { aqiRow(label: String(localized: "Luft"), value: $0) },
            value(hourly?.uv_index).flatMap(uvRow),
            worstPollen ?? worstPollutant,
        ].compactMap { $0 }
    }

    static func aqiRow(label: String, value: Double) -> AirRow? {
        EnvironmentMetric.forAQI(id: label, label: label, value: value).map {
            AirRow(label: label, status: EUAirQualityBand(value: value).localizedStatus, value: Int(value.rounded()), metric: $0)
        }
    }

    static func uvRow(_ value: Double) -> AirRow? {
        EnvironmentMetric.forUV(value: value).map {
            AirRow(label: "UV", status: UVIndexCategory(uvIndex: value).localizedTitle, value: Int(value.rounded()), metric: $0)
        }
    }

    static func pollenRow(type: PollenType, label: String, value: Double) -> AirRow? {
        EnvironmentMetric.forPollen(type: type, label: label, value: value).map {
            AirRow(label: label, status: pollenStatus(type.tier(for: value)), value: Int(value.rounded()), metric: $0)
        }
    }

    private static func worstPollenRow(_ candidates: [(type: PollenType, label: String, value: Double?)]) -> AirRow? {
        let worst = candidates
            .compactMap { candidate -> (type: PollenType, label: String, value: Double)? in
                guard let value = candidate.value, candidate.type.tier(for: value) > .none else { return nil }
                return (candidate.type, candidate.label, value)
            }
            .max { ($0.type.tier(for: $0.value), $0.value) < ($1.type.tier(for: $1.value), $1.value) }
        return worst.flatMap { pollenRow(type: $0.type, label: $0.label, value: $0.value) }
    }

    private static func worstPollutantRow(_ candidates: [(label: String, value: Double?)]) -> AirRow? {
        let worst = candidates
            .compactMap { candidate in candidate.value.map { (label: candidate.label, value: $0) } }
            .max { $0.value < $1.value }
        return worst.flatMap { aqiRow(label: $0.label, value: $0.value) }
    }

    private static func pollenStatus(_ tier: PollenTier) -> String {
        switch tier {
        case .none: String(localized: "Keine")
        case .low: String(localized: "Gering")
        case .moderate: String(localized: "Mäßig")
        case .high: String(localized: "Hoch")
        case .veryHigh: String(localized: "Sehr Hoch")
        }
    }
}

struct AirWidgetView: View {
    let entry: AirEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: entry.location)
                .font(.subheadline.weight(.semibold))
            if entry.rows.isEmpty {
                Spacer(minLength: 0)
                Text("Keine Luftdaten")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            ForEach(entry.rows) { row in
                Spacer(minLength: 0)
                AirRowView(row: row)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(LinearGradient.calmDay, for: .widget)
        .widgetURL(.oscarPlace(entry.cityID))
    }
}

private struct AirRowView: View {
    let row: AirRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: row.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: row.status)
                    .font(.caption.weight(.semibold))
                Text(row.value, format: .number)
                    .font(.headline)
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .trailing)
            }
            AirBar(gradient: row.metric.gradient, fraction: row.metric.severityFraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(row.label), \(row.status), \(row.value)"))
    }
}

private struct AirBar: View {
    let gradient: Gradient
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
            .frame(height: 5)
            .overlay {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.white)
                        .frame(width: 3, height: 9)
                        .shadow(color: .black.opacity(0.25), radius: 0.5)
                        .widgetAccentable()
                        .position(x: proxy.size.width * min(max(fraction, 0), 1), y: proxy.size.height / 2)
                }
            }
    }
}

struct AirWidget: Widget {
    let kind: String = "AirWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: AirProvider()) { entry in
            AirWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Luft"))
        .description(String(localized: "Luftqualität, UV-Index und Pollen für deinen Ort."))
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    AirWidget()
} timeline: {
    AirEntry(date: .now, location: "Leipzig", rows: [
        AirProvider.aqiRow(label: "Luft", value: 32),
        AirProvider.uvRow(1),
        AirProvider.aqiRow(label: "PM2,5", value: 14),
    ].compactMap { $0 })
    AirEntry(date: .now, location: "München", rows: [
        AirProvider.aqiRow(label: "Luft", value: 58),
        AirProvider.uvRow(6),
        AirProvider.pollenRow(type: .birch, label: "Birke", value: 120),
    ].compactMap { $0 })
    AirEntry(date: .now, location: "Leipzig", rows: [])
}
