// Lock screen widget with the temperature line of the next six hours.
import SwiftUI
import WidgetKit

struct HourlyLockScreenEntry: TimelineEntry {
    struct Hour {
        let time: Date
        let temperature: Double
    }

    let date: Date
    let place: String
    let temperatureNow: Double?
    let hours: [Hour]
    var timeZone: TimeZone = .current
    var cityID: String? = nil
}

struct HourlyLockScreenProvider: PlaceTimelineSource {
    let refreshMinutes = 30

    func placeholder(in context: Context) -> HourlyLockScreenEntry {
        HourlyLockScreenEntry(date: Date(), place: "Berlin", temperatureNow: 7, hours: Self.sampleHours(Date()))
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [HourlyLockScreenEntry] {
        let (weather, _) = try await WidgetForecast.forecast(place.coordinates)
        let placeName = await place.locationName()
        let times = weather.hourly?.time ?? []
        let temperatures = weather.hourly?.temperature_2m ?? []
        let hours = zip(times, temperatures).map { HourlyLockScreenEntry.Hour(time: Date(timeIntervalSince1970: $0), temperature: $1) }

        return nowcastEntryDates(refreshMinutes: refreshMinutes).map { date in
            HourlyLockScreenEntry(
                date: date,
                place: placeName,
                temperatureNow: weather.current?.temperature,
                hours: Array(hours.filter { $0.time > date }.prefix(6)),
                timeZone: weather.locationTimeZone,
                cityID: place.cityID
            )
        }
    }

    static func sampleHours(_ now: Date) -> [HourlyLockScreenEntry.Hour] {
        let start = Calendar.current.dateInterval(of: .hour, for: now)?.end ?? now
        return [8, 7, 6, 5, 5, 4].enumerated().map { index, temperature in
            HourlyLockScreenEntry.Hour(time: start.addingTimeInterval(Double(index) * 3600), temperature: temperature)
        }
    }
}

struct HourlyLockScreenView: View {
    let entry: HourlyLockScreenEntry
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(entry.place)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(units.temperatureString(entry.temperatureNow, placeholder: "–"))
            }
            .font(.system(size: 13, weight: .semibold))
            .widgetAccentable()

            HourlyTemperatureLine(values: entry.hours.map(\.temperature))
                .frame(height: 22)

            HStack(spacing: 0) {
                ForEach(entry.hours, id: \.time) { hour in
                    VStack(spacing: 0) {
                        Text(SettingService.formattedHour(hour.time, timeZone: entry.timeZone))
                            .font(.system(size: 9, weight: .semibold))
                        Text(units.temperatureString(hour.temperature))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .containerBackground(.clear, for: .widget)
        .widgetURL(.oscarPlace(entry.cityID))
    }

    private func hourLabel(_ time: Date) -> String {
        SettingService.formattedTime(time, timeZone: entry.timeZone, showsMinutes: false)
    }

    private var accessibilityText: String {
        let hours = entry.hours.map { "\(hourLabel($0.time)): \(units.temperatureString($0.temperature))" }
        return ([entry.place, units.temperatureString(entry.temperatureNow, placeholder: "–")] + hours)
            .joined(separator: ", ")
    }
}

private struct HourlyTemperatureLine: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = linePoints(in: proxy.size)
            Path { $0.addLines(points) }
                .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if let first = points.first {
                Circle()
                    .fill(.primary)
                    .frame(width: 5, height: 5)
                    .position(first)
            }
        }
    }

    private func linePoints(in size: CGSize) -> [CGPoint] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let middle = (low + high) / 2
        let span = max(high - low, 4)
        let inset: CGFloat = 3
        let usableHeight = size.height - inset * 2
        return values.enumerated().map { index, value in
            let x = size.width * (CGFloat(index) + 0.5) / CGFloat(values.count)
            let fraction = (value - middle) / span + 0.5
            return CGPoint(x: x, y: inset + usableHeight * (1 - CGFloat(fraction)))
        }
    }
}

struct HourlyLockScreenWidget: Widget {
    let kind: String = "HourlyLockScreenWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: HourlyLockScreenProvider()) { entry in
            HourlyLockScreenView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Nächste Stunden", comment: "LS Widget Nächste Stunden"))
        .description(String(localized: "Temperaturverlauf der nächsten sechs Stunden", comment: "LS Widget Nächste Stunden Beschreibung"))
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview("Nächste Stunden", as: .accessoryRectangular) {
    HourlyLockScreenWidget()
} timeline: {
    HourlyLockScreenEntry(date: .now, place: "Leipzig", temperatureNow: 7, hours: HourlyLockScreenProvider.sampleHours(.now))
    HourlyLockScreenEntry(date: .now, place: "Leipzig", temperatureNow: nil, hours: [])
}
