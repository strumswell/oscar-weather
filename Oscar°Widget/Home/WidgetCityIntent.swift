//
//  WidgetCityIntent.swift
//  Oscar°
//
//  The configurable-city options and intent for the DailyForecastWidget.
//

import AppIntents
import CoreData
import Foundation
import WidgetKit

// MARK: - Configurable city

struct WidgetCityOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let cities = [WidgetCity.currentLocation] + savedCities()
        let items = cities.map { city in
            IntentItem(city.id, title: "\(city.name)")
        }

        return IntentItemCollection {
            IntentItemSection(items: items)
        }
    }

    /// Saved cities from the Core Data store shared via the app group.
    private func savedCities() -> [WidgetCity] {
        let context = PersistenceController.shared.container.viewContext
        return context.performAndWait {
            // Drop cached snapshots first so cities the app added/renamed are read fresh.
            context.refreshAllObjects()
            let request: NSFetchRequest<City> = City.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            guard let results = try? context.fetch(request) else { return [] }
            return results.compactMap { city in
                guard let label = city.label else { return nil }
                return WidgetCity(
                    id: WidgetCity.makeID(latitude: city.lat, longitude: city.lon, name: label),
                    name: label,
                    latitude: city.lat,
                    longitude: city.lon
                )
            }
        }
    }

    func defaultResult() async -> String? {
        WidgetCity.currentLocationID
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ort wählen"
    static let description = IntentDescription("Wähle den Ort für die Tagesvorhersage.")

    @Parameter(title: "Ort", optionsProvider: WidgetCityOptionsProvider())
    var city: String?
}
