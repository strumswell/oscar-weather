//
//  NowViewModel.swift
//  Weather
//
// TODO: I need to clean/ break this up...
//
//  Created by Philipp Bolte on 17.12.20.
//
import Foundation
import CoreLocation
import Combine
import SwiftUI
import SPIndicator
import Networking

class NowViewModel: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var lm: LocationManager = LocationManager()
    @Published var cs: LocationViewModel = LocationViewModel()
    @Published var updateDidFinish: Bool = true
    
    var anyCancellable = Set<AnyCancellable>()
        
    let dispatchGroup =  DispatchGroup()
    private let defaultCoordinates = CLLocationCoordinate2D(latitude: 52.01, longitude: 10.77)
        
    let objectWillChange = ObservableObjectPublisher()
    
    var weather: WeatherResponse? {
        willSet {
            objectWillChange.send()
        }
    }
    
    var currentRadarMetadata: WeatherMapsResponse? {
        willSet {
            objectWillChange.send()
        }
    }
    
    var placemark: CLPlacemark? {
        willSet {
            objectWillChange.send()
        }
    }

    
    override init() {
        super.init()
        
        lm.objectWillChange.sink {
            self.objectWillChange.send()
        }
        .store(in: &anyCancellable)
        
        cs.objectWillChange.sink {
            self.objectWillChange.send()
        }
        .store(in: &anyCancellable)
    
        fetchCurrentRadarMetadata(dispatchGroup: dispatchGroup)
    }
    
    func update() {
        cs.update()
        lm.update()
        
        fetchCurrentPlacemark(dispatchGroup: dispatchGroup)
        fetchCurrentWeather(dispatchGroup: dispatchGroup)
        fetchCurrentRadarMetadata(dispatchGroup: dispatchGroup)
    }
    
    func getActiveLocation() -> CLLocationCoordinate2D {
        var coordinates: CLLocationCoordinate2D
        let selectedCities = cs.cities.filter{$0.selected}
        
        if (selectedCities.count > 0) {
            let city = selectedCities.first!
            coordinates = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
        } else {
            let coords = lm.gpsLocation ?? defaultCoordinates
            coordinates = CLLocationCoordinate2D(latitude: coords.latitude, longitude: coords.longitude)
        }
        return coordinates
    }
    
    /*
     * Fetch placemark object of users current location
     */
    func fetchCurrentPlacemark(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        
        // Get weather location
        var location: CLLocation
        let selectedCities = cs.cities.filter{$0.selected}
        
        if (selectedCities.count > 0) {
            let city = selectedCities.first!
            location = CLLocation(latitude: city.lat, longitude: city.lon)
        } else {
            let coords = lm.gpsLocation ?? defaultCoordinates
            location = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
        }
        
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location,
                                        completionHandler: {
                                            (placemarks, error) in
                                            if error == nil {
                                                let firstLocation = placemarks?[0]
                                                self.placemark = firstLocation
                                                print("Fetched Placemark")
                                                dispatchGroup.leave()
                                            } else {
                                                self.updateDidFinish = false
                                                print("Error fetching Coordinates")
                                                
                                                dispatchGroup.leave()
                                            }
                                        })
    }
    
    /*
     * Fetch weather of current user location via external service
     * Credits: https://www.hackingwithswift.com/books/ios-swiftui/sending-and-receiving-codable-data-with-urlsession-and-swiftui
     */
    func fetchCurrentWeather(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        
        // Get weather location
        var coordinates: CLLocationCoordinate2D
        let selectedCities = cs.cities.filter{$0.selected}
        
        if (selectedCities.count > 0) {
            let city = selectedCities.first!
            coordinates = CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
        } else {
            let coords = lm.gpsLocation ?? defaultCoordinates
            coordinates = CLLocationCoordinate2D(latitude: coords.latitude, longitude: coords.longitude)
        }
    
        let networking = Networking(baseURL: "https://radar.bolte.cloud/api/v2")
        networking.get("/weather/forecast?lat=\(coordinates.latitude)&lon=\(coordinates.longitude)&key=4d0ddebf-918f-495c-bc9c-fefa333a30c7") { result in
            switch result {
            case .success(let response):
                if let decodedResponse = try? JSONDecoder().decode(WeatherResponse.self, from: response.data) {
                    DispatchQueue.main.async {
                        self.weather = decodedResponse.self
                        print("Fetched Weather")
                        dispatchGroup.leave()
                    }
                    return
                }
            case .failure(let response):
                self.updateDidFinish = false
                print(response.statusCode)
                dispatchGroup.leave()
            }
        }

    }
    
    func fetchCurrentRadarMetadata(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        
        let networking = Networking(baseURL: "https://api.rainviewer.com")
        networking.get("/public/weather-maps.json") { result in
            switch result {
            case .success(let response):
                if let decodedResponse = try? JSONDecoder().decode(WeatherMapsResponse.self, from: response.data) {
                    DispatchQueue.main.async {
                        self.currentRadarMetadata = decodedResponse.self
                        print("Fetched Radar Metadata")
                        dispatchGroup.leave()
                    }
                    return
                }
            case .failure(let response):
                print(response.statusCode)
                self.updateDidFinish = false
                dispatchGroup.leave()
            }
        }
    }
}
