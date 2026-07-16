//
//  CityService.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.08.21.
//
import CoreData
import CoreLocation
import SwiftUI
import WidgetKit
import OSLog

@MainActor
@Observable
public final class CityService {
    static let shared = CityService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Storage"
    )
    var cities: [City]

    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default

    private init() {
        self.cities = []
        self.context = pc.container.viewContext
        self.currentLocationEmoji = UserDefaults.standard.string(forKey: Self.currentLocationEmojiKey)
        self.currentLocationCustomLabel = UserDefaults.standard.string(forKey: Self.currentLocationLabelKey)
        // Current location IS the default until the user explicitly chooses
        // otherwise (registered defaults are per-launch and never persisted, so
        // any explicit choice — city default or "no default" — wins forever).
        UserDefaults.standard.register(defaults: [Self.defaultIsCurrentLocationKey: true])
        self.defaultIsCurrentLocation = UserDefaults.standard.bool(forKey: Self.defaultIsCurrentLocationKey)
        self.update()
    }
    
    private func save() {
        do {
            try self.context.save()
            update()
            nc.post(name: .cityToggle, object: nil)
            nc.post(name: .weatherRefreshNeeded, object: nil)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.logger.error("City save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
        }
    }
    
    func update() {
        do {
            self.context.refreshAllObjects()
            let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            self.cities = try self.context.fetch(fetchRequest)
        } catch {
            Self.logger.error("City fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    func addCity(searchResult: Components.Schemas.Location) {
        guard let lat = searchResult.latitude, let lon = searchResult.longitude else {
            return
        }
        addCity(name: searchResult.name ?? "", latitude: Double(lat), longitude: Double(lon))
    }

    func addCity(name: String, latitude: Double, longitude: Double) {
        if let existingCity = self.getExistingCity(latitude: latitude, longitude: longitude) {
            self.toggleActiveCity(city: existingCity)
        } else {
            let newCity = City(context: self.context)
            newCity.label = name
            newCity.lat = latitude
            newCity.lon = longitude
            newCity.selected = false
            newCity.orderIndex = self.getMaxOrderIndex() + 1

            save()
            self.toggleActiveCity(city: newCity)
        }
    }

    func updateCity(_ city: City, emoji: String?, customLabel: String?) {
        let trimmedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        city.emoji = (emoji?.isEmpty == false) ? emoji : nil
        city.customLabel = (trimmedLabel?.isEmpty == false) ? trimmedLabel : nil
        save()
    }
    
    func deleteCity(offsets: IndexSet) {
        offsets.map { cities[$0] }.forEach(context.delete)
        let remainingCities = cities.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        for (index, city) in remainingCities.enumerated() {
            city.orderIndex = Int64(index)
        }
        save()
    }
    
    func disableAllCities() {
        for city in cities {
            city.selected = false
        }
        save()
    }
    
    func toggleActiveCity(city: City) {
        // Deselect all cities
        for city in cities {
            city.selected = false
        }
        // Select the clicked city
        city.selected = true
        self.save()
    }
    
    func moveCity(from source: IndexSet, to destination: Int) {
        var revisedCities = cities
        revisedCities.move(fromOffsets: source, toOffset: destination)

        // Update the orderIndex to reflect the new order
        for (index, city) in revisedCities.enumerated() {
            city.orderIndex = Int64(index)
        }

        // Save the updated order to the context
        save()
    }


    /// The GPS "current location" entry can be personalized like a saved city,
    /// but it is no City entity — emoji and label live in UserDefaults, mirrored
    /// into observable storage so views react to edits.
    static let currentLocationEmojiKey = "currentLocationEmoji"
    static let currentLocationLabelKey = "currentLocationCustomLabel"

    private(set) var currentLocationEmoji: String?
    private(set) var currentLocationCustomLabel: String?

    /// The current-location card title: a custom label wins over the generic name.
    var currentLocationDisplayName: String {
        if let currentLocationCustomLabel, !currentLocationCustomLabel.isEmpty {
            return currentLocationCustomLabel
        }
        return String(localized: "Aktueller Standort")
    }

    func updateCurrentLocation(emoji: String?, customLabel: String?) {
        let trimmedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationEmoji = (emoji?.isEmpty == false) ? emoji : nil
        currentLocationCustomLabel = (trimmedLabel?.isEmpty == false) ? trimmedLabel : nil
        UserDefaults.standard.set(currentLocationEmoji, forKey: Self.currentLocationEmojiKey)
        UserDefaults.standard.set(currentLocationCustomLabel, forKey: Self.currentLocationLabelKey)
    }

    /// Which location the app opens with. Stored across two places by necessity:
    /// a saved city carries `isDefault`; "current location" is no city at all, so
    /// that choice lives in UserDefaults.
    static let defaultIsCurrentLocationKey = "defaultLocationIsCurrentLocation"

    var defaultCity: City? {
        cities.first { $0.isDefault }
    }

    /// Stored (not computed off UserDefaults) so it is observable: the list
    /// card and swipe/context buttons re-render the moment the default flips.
    private(set) var defaultIsCurrentLocation: Bool

    /// Marks a saved city as the launch default, or (nil + asCurrentLocation) the
    /// GPS location. Passing nil without asCurrentLocation clears any default.
    func setDefault(city: City?, asCurrentLocation: Bool = false) {
        defaultIsCurrentLocation = (city == nil && asCurrentLocation)
        UserDefaults.standard.set(defaultIsCurrentLocation, forKey: Self.defaultIsCurrentLocationKey)
        var changed = false
        for existing in cities where existing.isDefault != (existing === city) {
            existing.isDefault = (existing === city)
            changed = true
        }
        if changed {
            save()
        } else {
            // Only the current-location flag flipped (observable by itself);
            // the notification keeps non-observing listeners in sync.
            nc.post(name: .cityToggle, object: nil)
        }
    }

    /// Applies the launch default once at app start: a default city gets selected,
    /// a "current location" default clears any city selection. Without a default,
    /// the last selection persists (pre-default behavior).
    func applyDefaultSelectionOnLaunch() {
        if defaultIsCurrentLocation {
            // Only meaningful with GPS access — without it, clearing the city
            // selection would strand the app on the coordinate fallback (this
            // matters since current location is the default by default).
            let status = LocationService.shared.authStatus
            let gpsAvailable = status == .authorizedWhenInUse || status == .authorizedAlways
            if gpsAvailable, getSelectedCity() != nil {
                disableAllCities()
            }
        } else if let defaultCity, defaultCity.selected == false {
            toggleActiveCity(city: defaultCity)
        }
    }

    func getSelectedCity() -> Optional<City> {
        let selectedCities = self.cities.filter{$0.selected}
        if (selectedCities.isEmpty) {
            return nil
        }
        return selectedCities.first!
    }
    
    func getSelectedCityCoordinates() ->Optional<CLLocationCoordinate2D> {
        let selectedCity = getSelectedCity()
        if let city = selectedCity {
            return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
        }
        return nil
    }
    private func hasEntitiesWithoutOrderId() -> Bool {
        let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "orderIndex == nil")

        do {
            let results = try context.fetch(fetchRequest)
            return !results.isEmpty
        } catch {
            Self.logger.error("Error fetching entities without orderIndex: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    private func assignOrderIndexesToExistingEntities() {
        do {
            let fetchRequest: NSFetchRequest<City>
            fetchRequest = City.fetchRequest()
            let results = try self.context.fetch(fetchRequest)
            
            for (index, entity) in results.enumerated() {
                entity.orderIndex = Int64(index)
            }

            try context.save()
        } catch {
            Self.logger.error("Error assigning orderIndexes: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func getMaxOrderIndex() -> Int64 {
        let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
        let sortDescriptor = NSSortDescriptor(key: "orderIndex", ascending: false)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return results.first?.orderIndex ?? 0
        } catch {
            Self.logger.error("Error fetching max order index: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
    
    private func getExistingCity(latitude: Double, longitude: Double) -> City? {
        return self.cities.first { $0.lat == latitude && $0.lon == longitude }
    }
}

extension City {
    /// The user-facing name: a custom label ("Zuhause") wins over the place name.
    var displayName: String {
        if let customLabel, !customLabel.isEmpty {
            return customLabel
        }
        return label ?? ""
    }

    /// The place name as secondary line when a custom label is shown as title.
    var displayDetail: String? {
        guard let customLabel, !customLabel.isEmpty else { return nil }
        return label
    }
}
