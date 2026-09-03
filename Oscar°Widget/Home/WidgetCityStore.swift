import CoreData
import Foundation

/// Reads the saved cities from the Core Data store shared via the app group.
enum WidgetCityStore {
    static func savedCities() -> [WidgetCity] {
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
}
