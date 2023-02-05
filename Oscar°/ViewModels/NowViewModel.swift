//
//  NowViewModel.swift
//  Weather
//
//
//  Created by Philipp Bolte on 17.12.20.
//
import Foundation
import CoreLocation
import Combine
import SwiftUI
import SPIndicator
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
    var weather: OpenMeteoResponse? {
        willSet {
            objectWillChange.send()
        }
    }
    
    var aqi: AQIResponse? {
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
    
    var alerts: [DWDAlert]? {
        willSet {
            objectWillChange.send()
        }
    }
    
    var rain: RainRadarForecast? {
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
        fetchOpenMeteoData()
        fetchCurrentRainData(dispatchGroup: dispatchGroup)
        fetchWeatherAlerts()
        fetchCurrentRadarMetadata(dispatchGroup: dispatchGroup)
        fetchAQIData()
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func getCurrentCoords() -> CLLocationCoordinate2D {
        // Get weather location
        var coordinates: CLLocationCoordinate2D
        let selectedCities = cs.cities.filter{$0.selected}
        
        if (selectedCities.count > 0) {
            let city = selectedCities.first!
            coordinates = CLLocationCoordinate2D(latitude: round(city.lat * 1000) / 1000.0, longitude: round(city.lon * 1000) / 1000.0)
        } else {
            let coords = lm.gpsLocation ?? defaultCoordinates
            coordinates = CLLocationCoordinate2D(latitude: round(coords.latitude * 1000) / 1000.0, longitude: round(coords.longitude * 1000) / 1000.0)
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
        let url = "https://forecast.bolte.id/api/v3/weather/forecast?lat=\(coordinates.latitude)&lon=\(coordinates.longitude)&key=4d0ddebf-918f-495c-bc9c-fefa333a30c7"
        AF.request(url).validate().responseDecodable(of: BrightskyResponse.self) { response in
            switch response.result {
            case .success:
                //self.weather = response.value
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
    
    func fetchCurrentRainData(dispatchGroup: DispatchGroup) {
        dispatchGroup.enter()
        let url = "https://api.oscars.love/api/v1/rain?lat=\(getCurrentCoords().latitude.description)&lon=\(getCurrentCoords().longitude.description)"
        // Call rainviewer and get current tile URL
        AF.request(url).validate().responseDecodable(of: RainRadarForecast.self) { response in
            switch response.result {
            case .success:
                self.rain = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                dispatchGroup.leave()
            }
        }
    }
    
    func fetchWeatherAlerts() {
        let url: String = "https://api.oscars.love/api/v1/alerts?lat=\(getCurrentCoords().latitude.description)&lon=\(getCurrentCoords().longitude.description)"
        AF.request(url).validate().responseDecodable(of: DWDAlerts.self) { response in
            switch response.result {
            case .success:
                self.alerts = response.value
            case let .failure(error):
                print(error)
            }
        }
    }
    
    func fetchOpenMeteoData() {
        dispatchGroup.enter()
        let url: String = "https://api.open-meteo.com/v1/forecast?latitude=\(getCurrentCoords().latitude.description)&longitude=\(getCurrentCoords().longitude.description)&hourly=temperature_2m,apparent_temperature,surface_pressure,precipitation,weathercode,cloudcover,windspeed_10m,winddirection_10m,soil_temperature_6cm,soil_moisture_3_9cm&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum,precipitation_hours,windspeed_10m_max,winddirection_10m_dominant,shortwave_radiation_sum&current_weather=true&timeformat=unixtime&timezone=auto"
        AF.request(url).validate().responseDecodable(of: OpenMeteoResponse.self) { [self] response in
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
    
    func fetchAQIData() {
        dispatchGroup.enter()
        let url: String = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(getCurrentCoords().latitude.description)&longitude=\(getCurrentCoords().longitude.description)&hourly=european_aqi,european_aqi_pm2_5,european_aqi_pm10,european_aqi_no2,european_aqi_o3,european_aqi_so2,uv_index&timezone=auto"
        AF.request(url).validate().responseDecodable(of: AQIResponse.self) { [self] response in
            switch response.result {
            case .success:
                self.aqi = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                dispatchGroup.leave()
            }
        }
    }
}

