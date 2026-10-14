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
        self.currentLocationIconHidden = UserDefaults.standard.bool(forKey: Self.currentLocationIconHiddenKey)
        let hasExplicitDefaultChoice = UserDefaults.standard.object(forKey: Self.defaultIsCurrentLocationKey) != nil
        UserDefaults.standard.register(defaults: [Self.defaultIsCurrentLocationKey: true])
        self.defaultIsCurrentLocation = UserDefaults.standard.bool(forKey: Self.defaultIsCurrentLocationKey)
        self.update()
        if !UserDefaults.standard.bool(forKey: Self.defaultSelectionMigratedKey) {
            UserDefaults.standard.set(true, forKey: Self.defaultSelectionMigratedKey)
            if !hasExplicitDefaultChoice, getSelectedCity() != nil {
                defaultIsCurrentLocation = false
                UserDefaults.standard.set(false, forKey: Self.defaultIsCurrentLocationKey)
            }
        }
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
            newCity.orderIndex = self.getMaxOrderIndex() + 1
            self.toggleActiveCity(city: newCity)
        }
    }

    func updateCity(_ city: City, emoji: String?, customLabel: String?) {
        let trimmedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newEmoji = (emoji?.isEmpty == false) ? emoji : nil
        let newLabel = (trimmedLabel?.isEmpty == false) ? trimmedLabel : nil
        guard newEmoji != city.emoji || newLabel != city.customLabel else { return }
        city.emoji = newEmoji
        city.customLabel = newLabel
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
        for city in cities {
            city.selected = false
        }
        city.selected = true
        self.save()
    }

    func moveCity(from source: IndexSet, to destination: Int) {
        var revisedCities = cities
        revisedCities.move(fromOffsets: source, toOffset: destination)

        for (index, city) in revisedCities.enumerated() {
            city.orderIndex = Int64(index)
        }

        save()
    }


    static let currentLocationEmojiKey = "currentLocationEmoji"
    static let currentLocationLabelKey = "currentLocationCustomLabel"
    static let currentLocationIconHiddenKey = "currentLocationIconHidden"

    private(set) var currentLocationEmoji: String?
    private(set) var currentLocationCustomLabel: String?
    private(set) var currentLocationIconHidden: Bool

    var currentLocationDisplayName: String {
        currentLocationPersonalization.title
    }

    var currentLocationPersonalization: PlacePersonalization {
        let mark: PlacePersonalization.Mark
        if let currentLocationEmoji, !currentLocationEmoji.isEmpty {
            mark = .emoji(currentLocationEmoji)
        } else if currentLocationIconHidden {
            mark = .plain
        } else {
            mark = .locationGlyph
        }
        return PlacePersonalization(
            mark: mark,
            customLabel: (currentLocationCustomLabel?.isEmpty == false) ? currentLocationCustomLabel : nil,
            baseName: String(localized: "Mein Standort")
        )
    }

    func updateCurrentLocation(mark: PlacePersonalization.Mark, customLabel: String?) {
        let trimmedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        currentLocationEmoji = mark.emoji
        currentLocationCustomLabel = (trimmedLabel?.isEmpty == false) ? trimmedLabel : nil
        currentLocationIconHidden = (mark == .plain)
        UserDefaults.standard.set(currentLocationEmoji, forKey: Self.currentLocationEmojiKey)
        UserDefaults.standard.set(currentLocationCustomLabel, forKey: Self.currentLocationLabelKey)
        UserDefaults.standard.set(currentLocationIconHidden, forKey: Self.currentLocationIconHiddenKey)
    }

    static let defaultIsCurrentLocationKey = "defaultLocationIsCurrentLocation"
    static let defaultSelectionMigratedKey = "defaultLocationSelectionMigrated"

    var defaultCity: City? {
        cities.first { $0.isDefault }
    }

    private(set) var defaultIsCurrentLocation: Bool

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
            nc.post(name: .cityToggle, object: nil)
        }
    }

    func applyDefaultSelectionOnLaunch() {
        if defaultIsCurrentLocation {
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

struct PlacePersonalization: Equatable {
    enum Mark: Equatable {
        case plain
        case emoji(String)
        case locationGlyph

        var emoji: String? {
            if case .emoji(let value) = self { return value }
            return nil
        }
    }

    let mark: Mark
    let customLabel: String?
    let baseName: String

    var title: String { customLabel ?? baseName }

    var subtitle: String? { customLabel == nil ? nil : baseName }

    func detailLine(condition: String?) -> String? {
        let joined = [subtitle, condition].compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}

extension City {
    var displayName: String { personalization.title }

    var personalization: PlacePersonalization {
        PlacePersonalization(
            mark: emoji.flatMap { $0.isEmpty ? nil : PlacePersonalization.Mark.emoji($0) } ?? .plain,
            customLabel: (customLabel?.isEmpty == false) ? customLabel : nil,
            baseName: label ?? ""
        )
    }
}
