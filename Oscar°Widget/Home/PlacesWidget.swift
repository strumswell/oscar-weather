// The saved places in app order, each a small sky card, from one batched current-conditions request.
import CoreData
import CoreLocation
import SwiftUI
import WidgetKit

struct PlacesEntry: TimelineEntry {
    struct Row: Identifiable {
        let id: String
        let name: String
        let status: String
        let icon: String
        let temperature: Double
        let gradient: LinearGradient
    }

    let date: Date
    let rows: [Row]
}

struct PlacesProvider: TimelineProvider {
    private struct Place {
        let id: String
        let name: String
        let coordinates: CLLocationCoordinate2D
    }

    func placeholder(in context: Context) -> PlacesEntry {
        PlacesEntry(date: .now, rows: Array(PlacesEntry.previewRows.prefix(Self.limit(for: context.family))))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PlacesEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PlacesEntry>) -> Void) {
        let limit = Self.limit(for: context.family)
        Task {
            do {
                let entry = try await Self.entry(limit: limit)
                completion(Timeline(entries: [entry], policy: .after(minutesFromNow(60))))
            } catch {
                completion(Timeline(entries: [], policy: .after(minutesFromNow(15))))
            }
        }
    }

    private static func limit(for family: WidgetFamily) -> Int {
        family == .systemLarge ? 6 : 3
    }

    private static func entry(limit: Int) async throws -> PlacesEntry {
        let places = Array(await savedPlaces().prefix(limit))
        guard !places.isEmpty else { return PlacesEntry(date: .now, rows: []) }

        let coordinates = places.map(\.coordinates)
        let key = "places" + coordinates.map { WidgetCache.key("", $0) }.joined()
        let (batch, _) = try await WidgetCache.fetch(key, maxAge: 600) {
            try await CityConditionsStore.fetchBatch(coordinates: coordinates)
        }
        return PlacesEntry(date: .now, rows: await rows(places: places, batch: batch))
    }

    @MainActor
    private static func rows(places: [Place], batch: [BatchCurrentEntry]) -> [PlacesEntry.Row] {
        zip(places, batch).compactMap { place, item in
            guard let conditions = CityConditionsStore.makeConditions(
                entry: item, coordinate: place.coordinates, radar: nil
            ) else { return nil }
            return PlacesEntry.Row(
                id: place.id,
                name: place.name,
                status: conditions.conditionText,
                icon: WeatherSymbol.sfSymbol(weathercode: Double(conditions.weathercode), isDay: conditions.isDay),
                temperature: conditions.temperature,
                gradient: AtmosphereSampler.skyGradient(snapshot: conditions.snapshot)
            )
        }
    }

    @MainActor
    private static func savedPlaces() async -> [Place] {
        var places: [Place] = []
        let location = LocationService.shared
        location.updateGPSCoordinates()
        if let gps = location.knownGPSCoordinates() {
            let name = await location.getGPSPlacemarkInfo().name
            places.append(Place(
                id: WidgetCity.currentLocationID,
                name: name.isEmpty ? String(localized: "Mein Standort") : name,
                coordinates: LocationService.outboundCoordinate(gps)
            ))
        }

        let context = PersistenceController.shared.container.viewContext
        context.refreshAllObjects()
        let request: NSFetchRequest<City> = City.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
        for city in (try? context.fetch(request)) ?? [] {
            guard let label = city.label else { continue }
            places.append(Place(
                id: WidgetCity.makeID(latitude: city.lat, longitude: city.lon, name: label),
                name: city.displayName,
                coordinates: LocationService.outboundCoordinate(
                    CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                )
            ))
        }
        return places
    }
}

struct PlacesWidgetView: View {
    let entry: PlacesEntry

    var body: some View {
        Group {
            if entry.rows.isEmpty {
                Text("Füge in Oscar° Orte hinzu, um sie hier zu sehen.")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.rows) { row in
                        Link(destination: .oscarPlace(row.id)) {
                            PlaceRowView(row: row)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(8)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(Color.midnightStart, for: .widget)
        .widgetURL(.oscarPlace(nil))
    }
}

struct PlaceRowView: View {
    let row: PlacesEntry.Row
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.status)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: row.icon)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
            Text(units.temperatureString(row.temperature))
                .font(.title2)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: 64)
        .background {
            if renderingMode == .accented {
                Color.white.opacity(0.1)
            } else {
                row.gradient.overlay(Color.black.opacity(0.2))
            }
        }
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.name, row.status, units.temperatureString(row.temperature)].joined(separator: ", "))
    }
}

struct PlacesWidget: Widget {
    let kind: String = "PlacesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlacesProvider()) { entry in
            PlacesWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Orte"))
        .description(String(localized: "Deine Orte auf einen Blick."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

extension PlacesEntry {
    static let previewRows: [Row] = [
        Row(id: "leipzig", name: "Leipzig", status: "Teils bewölkt", icon: "cloud.sun.fill", temperature: 7,
            gradient: AtmosphereSampler.skyGradient(snapshot: .fallback)),
        Row(id: "hamburg", name: "Hamburg", status: "Regen", icon: "cloud.rain.fill", temperature: 6,
            gradient: AtmosphereSampler.skyGradient(snapshot: .twilight)),
        Row(id: "muenchen", name: "München", status: "Klar", icon: "sun.max.fill", temperature: 9,
            gradient: AtmosphereSampler.skyGradient(snapshot: .fallback)),
        Row(id: "koeln", name: "Köln", status: "Bedeckt", icon: "cloud.fill", temperature: 8,
            gradient: AtmosphereSampler.skyGradient(snapshot: .twilight)),
        Row(id: "dresden", name: "Dresden", status: "Nebel", icon: "cloud.fog.fill", temperature: 4,
            gradient: AtmosphereSampler.skyGradient(snapshot: .fallback)),
        Row(id: "berlin", name: "Berlin", status: "Klar", icon: "moon.stars.fill", temperature: 5,
            gradient: AtmosphereSampler.skyGradient(snapshot: .twilight)),
    ]
}

#Preview(as: .systemMedium) {
    PlacesWidget()
} timeline: {
    PlacesEntry(date: .now, rows: Array(PlacesEntry.previewRows.prefix(3)))
}

#Preview(as: .systemLarge) {
    PlacesWidget()
} timeline: {
    PlacesEntry(date: .now, rows: PlacesEntry.previewRows)
}
