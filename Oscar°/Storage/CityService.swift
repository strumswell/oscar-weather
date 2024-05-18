//
//  LocationViewModel.swift
//  LocationViewModel
//
//  Created by Philipp Bolte on 18.08.21.
//
import CoreData
import SwiftUI
import Combine
import MapKit
import WidgetKit

public class CityService: ObservableObject {

    @Published var cities: [City]

    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default

    init() {
        self.cities = []
        self.context = pc.container.viewContext
        self.update()
    }
    
    private func save() {
        do {
            try self.context.save()
            update()
            nc.post(name: Notification.Name("CityToggle"), object: nil)
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func update() {
        do {
            let fetchRequest: NSFetchRequest<City>
            fetchRequest = City.fetchRequest()
            self.cities = try self.context.fetch(fetchRequest)
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    #if os(iOS)
    func addCity(searchResult: MKLocalSearchCompletion) {
        self.getCoordinates(searchCompletion: searchResult) { coords in
            let label = searchResult.title.split(separator: ",")[0].description

            if ((self.cities.filter{$0.label == label}).count < 1) {
                let newCity = City(context: self.context)
                newCity.label = label
                newCity.lat = coords.latitude
                newCity.lon = coords.longitude
                newCity.selected = false
                                            
                self.save()
            } else {
                self.save()
            }
        }
    }
    #endif
    
    func addCity(city: Array<String>) {
        let newCity = City(context: self.context)
        newCity.label = city[0].split(separator: ",")[0].description
        newCity.lat = (city[1] as NSString).doubleValue
        newCity.lon = (city[2] as NSString).doubleValue
        newCity.selected = (city[3] as NSString).boolValue
        self.save()
    }
    
    func deleteCity(offsets: IndexSet) {
            offsets.map { cities[$0] }.forEach(context.delete)
            save()
    }
    
    func disableAllCities() {
        for city in cities {
            city.selected = false
        }
        save()
    }
    
    func toggleActiveCity(city: City) {
        if (city.selected) {
            city.selected = false
        } else {
            for city in cities {
                city.selected = false
            }
            city.selected = true
        }
        save()
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
    
    #if os(iOS)
    private func getCoordinates(searchCompletion: MKLocalSearchCompletion, completion: @escaping (CLLocationCoordinate2D) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: searchCompletion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            let coordinates = response?.mapItems[0].placemark.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            completion(coordinates)
        }
    }
    #endif
}

@Observable
public class CityServiceNew {
    var cities: [City]

    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default

    init() {
        self.cities = []
        self.context = pc.container.viewContext
        self.update()
    }
    
    private func save() {
        do {
            try self.context.save()
            update()
            nc.post(name: Notification.Name("CityToggle"), object: nil)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func update() {
        do {
            self.context.refreshAllObjects()
            let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "orderIndex", ascending: true)]
            self.cities = try self.context.fetch(fetchRequest)
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }

    func addCity(searchResult: Components.Schemas.Location) {
        guard let lat = searchResult.latitude, let lon = searchResult.longitude else {
            return
        }
        if let existingCity = self.getExistingCity(latitude: Double(lat), longitude: Double(lon)) {
            self.toggleActiveCity(city: existingCity)
        } else {
            let newCity = City(context: self.context)
            newCity.label = searchResult.name
            newCity.lat = Double(lat)
            newCity.lon = Double(lon)
            newCity.selected = false
            newCity.orderIndex = self.getMaxOrderIndex() + 1
            
            save()
            self.toggleActiveCity(city: newCity)
        }
    }
    
    func deleteCity(offsets: IndexSet) {
        let indicesToDelete = offsets.map { cities[$0].orderIndex }
        offsets.map { cities[$0] }.forEach(context.delete)
        save()
        updateOrderIndexesAfterDeletion(deletedIndices: indicesToDelete)
    }
    
    func disableAllCities() {
        for city in cities {
            city.selected = false
        }
        save()
        //nc.post(name: Notification.Name("CityToggle"), object: nil)
    }
    
    func toggleActiveCity(city: City) {
        if (city.selected) {
            city.selected = false
        } else {
            for city in cities {
                city.selected = false
            }
            city.selected = true
        }
        self.save()
        //nc.post(name: Notification.Name("CityToggle"), object: nil)
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
    
    #if os(iOS)
    private func getCoordinates(searchCompletion: MKLocalSearchCompletion, completion: @escaping (CLLocationCoordinate2D) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: searchCompletion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            let coordinates = response?.mapItems[0].placemark.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            completion(coordinates)
        }
    }
    #endif
    
    private func hasEntitiesWithoutOrderId() -> Bool {
        let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "orderIndex == nil")

        do {
            let results = try context.fetch(fetchRequest)
            return !results.isEmpty
        } catch {
            print("Error fetching entities without orderIndex: \(error)")
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
            print("Error assigning orderIndexes: \(error)")
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
            print("Error fetching max order index: \(error)")
            return 0
        }
    }
    
    private func updateOrderIndexesAfterDeletion(deletedIndices: [Int64]) {
        let fetchRequest: NSFetchRequest<City> = City.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "orderIndex > %@", argumentArray: deletedIndices)

        do {
            let results = try context.fetch(fetchRequest)
            for city in results {
                city.orderIndex -= Int64(deletedIndices.count)
            }
            try context.save()
        } catch {
            print("Error updating order indexes after deletion: \(error)")
        }
    }

    private func getExistingCity(latitude: Double, longitude: Double) -> City? {
        return self.cities.first { $0.lat == latitude && $0.lon == longitude }
    }
}




