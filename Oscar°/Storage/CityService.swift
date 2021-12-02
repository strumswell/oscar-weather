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
import SPIndicator

public class LocationViewModel: ObservableObject {
    
    @Published var cities: [City]

    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)


    init() {
        self.cities = []
        self.context = pc.container.viewContext
        self.update()
    }
    
    private func save() {
        do {
            try self.context.save()
            update()
            hapticFeedback.impactOccurred()
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

    func addCity(searchResult: MKLocalSearchCompletion) {
        self.getCoordinates(searchCompletion: searchResult) { coords in
            let label = searchResult.title.split(separator: ",")[0].description

            if ((self.cities.filter{$0.label == label}).count < 1) {
                let newCity = City(context: self.context)
                newCity.label = label
                newCity.lat = coords.latitude
                newCity.lon = coords.longitude
                newCity.selected = false
                
                print("\(newCity)")
                            
                self.save()
            } else {
                self.save()
            }
        }
    }
    
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
        save()
        //nc.post(name: Notification.Name("CityToggle"), object: nil)
    }
    
    private func getCoordinates(searchCompletion: MKLocalSearchCompletion, completion: @escaping (CLLocationCoordinate2D) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: searchCompletion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            let coordinates = response?.mapItems[0].placemark.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            print(coordinates)
            completion(coordinates)
        }
    }
}


