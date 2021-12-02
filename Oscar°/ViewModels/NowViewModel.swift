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
import WidgetKit
import Alamofire

class NowViewModel: NSObject, CLLocationManagerDelegate, ObservableObject {
    @Published var lm: LocationManager = LocationManager()
    @Published var cs: LocationViewModel = LocationViewModel()
    @Published var updateDidFinish: Bool = true
            
    let dispatchGroup =  DispatchGroup()
    private let defaultCoordinates = CLLocationCoordinate2D(latitude: 52.01, longitude: 10.77) // just in case...
    
    var anyCancellable = Set<AnyCancellable>()
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
    
    var alerts: [AWAlert]? {
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
    
    /*
     * Update all info like location, stored cities, forecast, and radar data
     */
    func update() {
        cs.update()
        lm.update()
        
        fetchCurrentPlacemark(dispatchGroup: dispatchGroup)
        fetchCurrentWeather(dispatchGroup: dispatchGroup)
        fetchWeatherAlerts()
        fetchCurrentRadarMetadata(dispatchGroup: dispatchGroup)
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func getCurrentCoords() -> CLLocationCoordinate2D {
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
        return coordinates
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
     */
    func fetchCurrentWeather(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        
        let coordinates = self.getCurrentCoords()
        let url = "https://forecast.bolte.id/api/v2/weather/forecast?lat=\(coordinates.latitude)&lon=\(coordinates.longitude)&key="
        AF.request(url).validate().responseDecodable(of: WeatherResponse.self) { response in
            switch response.result {
            case .success:
                self.weather = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                dispatchGroup.leave()
            }
        }
    }
    
    func fetchCurrentRadarMetadata(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        let url = "https://api.rainviewer.com/public/weather-maps.json"
        
        // Call rainviewer and get current tile URL
        AF.request(url).validate().responseDecodable(of: WeatherMapsResponse.self) { response in
            switch response.result {
            case .success:
                self.currentRadarMetadata = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                self.updateDidFinish = false
                dispatchGroup.leave()
            }
        }
    }
    
    func fetchWeatherAlerts() {
        let url: String = "https://forecast.bolte.id/api/v2/weather/alerts?key=&lat=\(getCurrentCoords().latitude.description)&lon=\(getCurrentCoords().longitude.description)"        
        AF.request(url).validate().responseDecodable(of: AlertResponse.self) { response in
            switch response.result {
            case .success:
                self.alerts = response.value
            case let .failure(error):
                print(error)
            }
        }
    }
}

