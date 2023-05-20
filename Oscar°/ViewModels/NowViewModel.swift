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
    @Published var time: Double = 1.0

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
    
    var placemark: String? {
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
        
        // Init Location and City model
        lm.objectWillChange.sink {
            self.objectWillChange.send()
        }
        .store(in: &anyCancellable)
        
        cs.objectWillChange.sink {
            self.objectWillChange.send()
        }
        .store(in: &anyCancellable)
    
        // For our Maplayer
        fetchCurrentRadarMetadata()
    }
    
    
    /*
     * Update all info like location, stored cities, forecast, and radar data
     */
    func update() {
        if !self.updateDidFinish {
            return
        }
        
        self.updateDidFinish = false

        cs.update()
        lm.update()
        
        fetchCurrentPlacemark()
        fetchOpenMeteoData()
        fetchCurrentRainData()
        fetchWeatherAlerts()
        fetchCurrentRadarMetadata()
        fetchAQIData()
        
        dispatchGroup.notify(queue: DispatchQueue.global()) {
            self.updateDidFinish = true
        }
        
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
    func fetchCurrentPlacemark() {
        dispatchGroup.enter()
        
        // Get weather location
        var location: CLLocation
        let selectedCities = cs.cities.filter{$0.selected}
        
        if (selectedCities.count > 0) {
            let city = selectedCities.first!
            self.placemark = city.label
            location = CLLocation(latitude: city.lat, longitude: city.lon)
            dispatchGroup.leave()
            return
        } else {
            let coords = lm.gpsLocation ?? defaultCoordinates
            location = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
        }
        
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location,
                                        completionHandler: {
            [self] (placemarks, error) in
                                            if error == nil {
                                                let firstLocation = placemarks?[0]
                                                self.placemark = firstLocation?.locality ?? "..."
                                                dispatchGroup.leave()
                                            } else {
                                                print("Error fetching Coordinates")
                                                dispatchGroup.leave()
                                            }
                                        })
    }
    
    /*
     * Fetch weather of current user location via external service
     */
    func fetchCurrentWeather() {
        dispatchGroup.enter()
        
        let coordinates = self.getCurrentCoords()
        let url = "https://forecast.bolte.id/api/v3/weather/forecast?lat=\(coordinates.latitude)&lon=\(coordinates.longitude)&key=4d0ddebf-918f-495c-bc9c-fefa333a30c7"
        AF.request(url).validate().responseDecodable(of: BrightskyResponse.self) { [self] response in
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
    
    func fetchCurrentRadarMetadata() {
        dispatchGroup.enter()
        let url = "https://api.rainviewer.com/public/weather-maps.json"
        
        // Call rainviewer and get current tile URL
        AF.request(url).validate().responseDecodable(of: WeatherMapsResponse.self) { [self] response in
            switch response.result {
            case .success:
                self.currentRadarMetadata = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                dispatchGroup.leave()
            }
        }
    }
    
    func fetchCurrentRainData() {
        dispatchGroup.enter()
        let url = "https://api.oscars.love/api/v1/rain?lat=\(getCurrentCoords().latitude.description)&lon=\(getCurrentCoords().longitude.description)"
        // Call rainviewer and get current tile URL
        AF.request(url).validate().responseDecodable(of: RainRadarForecast.self) { [self] response in
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
        dispatchGroup.enter()
        let url: String = "https://api.oscars.love/api/v1/alerts?lat=\(getCurrentCoords().latitude.description)&lon=\(getCurrentCoords().longitude.description)"
        AF.request(url).validate().responseDecodable(of: DWDAlerts.self) { [self] response in
            switch response.result {
            case .success:
                self.alerts = response.value
                dispatchGroup.leave()
            case let .failure(error):
                print(error)
                dispatchGroup.leave()
            }
        }
    }
    
    func fetchOpenMeteoData() {
        dispatchGroup.enter()
        let url: String = "https://api.open-meteo.com/v1/forecast?latitude=\(getCurrentCoords().latitude.description)&longitude=\(getCurrentCoords().longitude.description)&hourly=temperature_2m,apparent_temperature,surface_pressure,precipitation,weathercode,cloudcover,windspeed_10m,winddirection_10m,soil_temperature_6cm,soil_moisture_3_9cm,precipitation_probability&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum,precipitation_hours,windspeed_10m_max,winddirection_10m_dominant,shortwave_radiation_sum,precipitation_probability_max&current_weather=true&timeformat=unixtime&forecast_days=14&timezone=auto"
        AF.request(url).validate().responseDecodable(of: OpenMeteoResponse.self) { [self] response in
            switch response.result {
            case .success:
                self.weather = response.value
                let dayBegin = response.value!.hourly.time.first!
                // We take the time from the API to correctlz handle different timezones
                self.time = (Date.now.timeIntervalSince1970-dayBegin!)/86400.0
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
    
    func getBackgroundTopStops() -> [Gradient.Stop] {
        if (self.weather == nil) {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: 0.25),
                .init(color: .sunriseStart, location: 0.33),
                .init(color: .sunnyDayStart, location: 0.38),
                .init(color: .sunnyDayStart, location: 0.7),
                .init(color: .sunsetStart, location: 0.78),
                .init(color: .midnightStart, location: 0.82),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = self.weather!.hourly.time.first!
        let sunrise = self.weather!.daily.sunrise.first!
        let sunset = self.weather!.daily.sunset.first!
        
        if self.isRaining() {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: (sunrise - dayBegin!)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunrise - dayBegin!)/dayLength),
                .init(color: .rainyStart, location: (sunrise - dayBegin!)/dayLength + 0.05),
                .init(color: .rainyStart, location: (sunset - dayBegin!)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunset - dayBegin!)/dayLength),
                .init(color: .midnightStart, location: (sunset - dayBegin!)/dayLength + 0.04),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightStart, location: 0),
            .init(color: .midnightStart, location: (sunrise - dayBegin!)/dayLength - 0.08),
            .init(color: .sunriseStart, location: (sunrise - dayBegin!)/dayLength),
            .init(color: .sunnyDayStart, location: (sunrise - dayBegin!)/dayLength + 0.05),
            .init(color: .sunnyDayStart, location: (sunset - dayBegin!)/dayLength - 0.08),
            .init(color: .sunsetStart, location: (sunset - dayBegin!)/dayLength),
            .init(color: .midnightStart, location: (sunset - dayBegin!)/dayLength + 0.04),
            .init(color: .midnightStart, location: 1)
        ]

    }
    
    func getBackgroundBottomStops() -> [Gradient.Stop] {
        if (self.weather == nil) {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: 0.25),
                .init(color: .sunriseEnd, location: 0.33),
                .init(color: .sunnyDayEnd, location: 0.38),
                .init(color: .sunnyDayEnd, location: 0.7),
                .init(color: .sunsetEnd, location: 0.78),
                .init(color: .midnightEnd, location: 0.82),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = self.weather!.hourly.time.first!
        let sunrise = self.weather!.daily.sunrise.first!
        let sunset = self.weather!.daily.sunset.first!
        
        if self.isRaining() {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: (sunrise - dayBegin!)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunrise - dayBegin!)/dayLength),
                .init(color: .rainyEnd, location: (sunrise - dayBegin!)/dayLength + 0.05),
                .init(color: .rainyEnd, location: (sunset - dayBegin!)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunset - dayBegin!)/dayLength),
                .init(color: .midnightEnd, location: (sunset - dayBegin!)/dayLength + 0.04),
                .init(color: .midnightEnd, location: 1)
            ]
        }

        return [
            .init(color: .midnightEnd, location: 0),
            .init(color: .midnightEnd, location: (sunrise - dayBegin!)/dayLength - 0.08),
            .init(color: .sunriseEnd, location: (sunrise - dayBegin!)/dayLength),
            .init(color: .sunnyDayEnd, location: (sunrise - dayBegin!)/dayLength + 0.05),
            .init(color: .sunnyDayEnd, location: (sunset - dayBegin!)/dayLength - 0.08),
            .init(color: .sunsetStart, location: (sunset - dayBegin!)/dayLength),
            .init(color: .midnightEnd, location: (sunset - dayBegin!)/dayLength + 0.04),
            .init(color: .midnightEnd, location: 1)
        ]
    }
    
    func getCloudTopStops() -> [Gradient.Stop] {
        if (self.weather == nil) {
            return [
                .init(color: .darkCloudStart, location: 0),
                .init(color: .darkCloudStart, location: 0.25),
                .init(color: .sunriseCloudStart, location: 0.33),
                .init(color: .lightCloudStart, location: 0.38),
                .init(color: .lightCloudStart, location: 0.7),
                .init(color: .sunsetCloudStart, location: 0.78),
                .init(color: .darkCloudStart, location: 0.82),
                .init(color: .darkCloudStart, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = self.weather!.hourly.time.first!
        let sunrise = self.weather!.daily.sunrise.first!
        let sunset = self.weather!.daily.sunset.first!
        
        if self.isRaining() {
            return [
                .init(color: .darkCloudStart, location: 0),
                .init(color: .darkCloudStart, location: (sunrise - dayBegin!)/dayLength - 0.08),
                .init(color: .rainCloudStart, location: (sunrise - dayBegin!)/dayLength),
                .init(color: .rainCloudStart, location: (sunrise - dayBegin!)/dayLength + 0.05),
                .init(color: .rainCloudStart, location: (sunset - dayBegin!)/dayLength - 0.08),
                .init(color: .rainCloudStart, location: (sunset - dayBegin!)/dayLength),
                .init(color: .darkCloudStart, location: (sunset - dayBegin!)/dayLength + 0.04),
                .init(color: .darkCloudStart, location: 1)
            ]
        }

        return [
            .init(color: .darkCloudStart, location: 0),
            .init(color: .darkCloudStart, location: (sunrise - dayBegin!)/dayLength - 0.08),
            .init(color: .sunriseCloudStart, location: (sunrise - dayBegin!)/dayLength),
            .init(color: .lightCloudStart, location: (sunrise - dayBegin!)/dayLength + 0.05),
            .init(color: .lightCloudStart, location: (sunset - dayBegin!)/dayLength - 0.08),
            .init(color: .sunsetCloudStart, location: (sunset - dayBegin!)/dayLength),
            .init(color: .darkCloudStart, location: (sunset - dayBegin!)/dayLength + 0.04),
            .init(color: .darkCloudStart, location: 1)
        ]
    }
    
    func getCloudBottomStops() -> [Gradient.Stop] {
        if (self.weather == nil) {
            return [
                .init(color: .darkCloudEnd, location: 0),
                .init(color: .darkCloudEnd, location: 0.25),
                .init(color: .sunriseCloudEnd, location: 0.33),
                .init(color: .lightCloudEnd, location: 0.38),
                .init(color: .lightCloudEnd, location: 0.7),
                .init(color: .sunsetCloudEnd, location: 0.78),
                .init(color: .darkCloudEnd, location: 0.92),
                .init(color: .darkCloudEnd, location: 1)
            ]
        }
        
        let dayLength = 86400.0
        let dayBegin = self.weather!.hourly.time.first!
        let sunrise = self.weather!.daily.sunrise.first!
        let sunset = self.weather!.daily.sunset.first!
        
        if self.isRaining() {
            return [
                .init(color: .darkCloudEnd, location: 0),
                .init(color: .darkCloudEnd, location: (sunrise - dayBegin!)/dayLength - 0.08),
                .init(color: .rainCloudEnd, location: (sunrise - dayBegin!)/dayLength),
                .init(color: .rainCloudEnd, location: (sunrise - dayBegin!)/dayLength + 0.05),
                .init(color: .rainCloudEnd, location: (sunset - dayBegin!)/dayLength - 0.08),
                .init(color: .rainCloudEnd, location: (sunset - dayBegin!)/dayLength),
                .init(color: .darkCloudEnd, location: (sunset - dayBegin!)/dayLength + 0.04),
                .init(color: .darkCloudEnd, location: 1)
            ]
        }

        return [
            .init(color: .darkCloudEnd, location: 0),
            .init(color: .darkCloudEnd, location: (sunrise - dayBegin!)/dayLength - 0.08),
            .init(color: .sunriseCloudEnd, location: (sunrise - dayBegin!)/dayLength),
            .init(color: .lightCloudEnd, location: (sunrise - dayBegin!)/dayLength + 0.05),
            .init(color: .lightCloudEnd, location: (sunset - dayBegin!)/dayLength - 0.08),
            .init(color: .sunsetCloudEnd, location: (sunset - dayBegin!)/dayLength),
            .init(color: .darkCloudEnd, location: (sunset - dayBegin!)/dayLength + 0.04),
            .init(color: .darkCloudEnd, location: 1)
        ]
    }
    
    let starStops: [Gradient.Stop] = [
        .init(color: .white, location: 0),
        .init(color: .white, location: 0.25),
        .init(color: .clear, location: 0.33),
        .init(color: .clear, location: 0.38),
        .init(color: .clear, location: 0.7),
        .init(color: .clear, location: 0.78),
        .init(color: .white, location: 0.82),
        .init(color: .white, location: 1)
    ]

    var starOpacity: Double {
        let color = starStops.interpolated(amount: self.time)
        return color.getComponents().alpha
    }
    
    func isRaining() -> Bool {
        if self.weather?.currentWeather.getStormType() != Storm.Contents.none || (self.rain?.data.first?.mmh ?? 0.0) > 0.0 {
            return true
        }
        return false
    }
}

