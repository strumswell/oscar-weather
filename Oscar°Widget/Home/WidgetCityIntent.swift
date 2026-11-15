//
//  WidgetCityIntent.swift
//  Oscar°
//
//  The configurable-city options and intent shared by the iOS widgets.
//

import AppIntents
import CoreData
import Foundation
import WidgetKit

// MARK: - Configurable city

struct WidgetPlaceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ort")
    static let defaultQuery = WidgetPlaceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetPlaceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetPlaceEntity] {
        let places = allPlaces()
        return identifiers.compactMap { id in
            places.first { $0.id == id } ?? WidgetCity(id: id).map { WidgetPlaceEntity(id: id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [WidgetPlaceEntity] {
        allPlaces()
    }

    func defaultResult() async -> WidgetPlaceEntity? {
        allPlaces().first
    }

    private func allPlaces() -> [WidgetPlaceEntity] {
        ([WidgetCity.currentLocation] + savedCities()).map { WidgetPlaceEntity(id: $0.id, name: $0.name) }
    }

    private func savedCities() -> [WidgetCity] {
        let context = PersistenceController.shared.container.viewContext
        return context.performAndWait {
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
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ort wählen"
    static let description = IntentDescription("Wähle den Ort für dieses Widget.")

    @Parameter(title: "Ort")
    var city: WidgetPlaceEntity?
}
