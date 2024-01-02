//
//  HomeProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import Alamofire

struct HomeEntry: TimelineEntry {
    let date: Date
    let location: String
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let precipitation: Double
    let precipitationProbability: Int
    let backgroundGradients: [Color]
}

class HomeProvider: TimelineProvider {
    var lm: LocationManager
    let defaultCoordinate = CLLocationCoordinate2D.init(latitude: 52.42, longitude: 12.52)
    let dispatchGroup =  DispatchGroup()
    
    var placemark: String?
    var weather: OMDayTemperature?
    var time: Double?
    
    init() {
        lm = LocationManager()
        lm.update()
    }
    
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: Date(), location: "Leipzig", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72, backgroundGradients: [.sunriseStart, .sunnyDayEnd])
    }
    
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> ()) {
        let entry = HomeEntry(date: Date(), location: "Leipzig", temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72, backgroundGradients: [.sunriseStart, .sunnyDayEnd])
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> ()) {
        lm.update()
        
        let currentDate = Date()
        let coordinates = lm.gpsLocation ?? self.defaultCoordinate
        
        self.fetchCurrentPlacemark(coordinates: coordinates)
        self.fetchWeatherData(coordinates: coordinates)
                
        dispatchGroup.notify(queue: DispatchQueue.global()) {
            if (self.weather == nil || self.placemark == nil) {
                return
            }
            
            let entry = HomeEntry(
                date: Date(),
                location: self.placemark ?? "Unknown",
                temperatureMin: self.weather?.daily.temperature2MMin.first ?? 0.0,
                temperatureMax: self.weather?.daily.temperature2MMax.first ?? 0.0,
                temperatureNow: self.weather?.currentWeather.temperature ?? 0.0,
                icon: self.weather?.currentWeather.getWeatherIcon() ?? "cloud.fill",
                precipitation: self.weather?.hourly.precipitation.first ?? 0.0,
                precipitationProbability: self.weather?.hourly.precipitationProbability.first ?? 0,
                backgroundGradients: [
                    self.getBackgroundTopStops().interpolated(amount: self.time!),
                    self.getBackgroundBottomStops().interpolated(amount: self.time!)
                ]
            )
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
            let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }
    
    func getBackgroundTopStops() -> [Gradient.Stop] {
        let dayLength = 86400.0
        let dayBegin = Double(self.weather!.hourly.time.first!)
        let sunrise = Double(self.weather!.daily.sunrise.first!)
        let sunset = Double(self.weather!.daily.sunset.first!)
        let isRaining = self.weather!.currentWeather.weathercode >= 51 && self.weather!.currentWeather.weathercode <= 99

        if isRaining {
            return [
                .init(color: .midnightStart, location: 0),
                .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyStart, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyStart, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
                .init(color: .midnightStart, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightStart, location: 0),
            .init(color: .midnightStart, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseStart, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayStart, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayStart, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetStart, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightStart, location: (sunset - dayBegin)/dayLength + 0.04),
            .init(color: .midnightStart, location: 1)
        ]
        
    }
    
    func getBackgroundBottomStops() -> [Gradient.Stop] {
        let dayLength = 86400.0
        let dayBegin = Double(self.weather!.hourly.time.first!)
        let sunrise = Double(self.weather!.daily.sunrise.first!)
        let sunset = Double(self.weather!.daily.sunset.first!)
        let isRaining = self.weather!.currentWeather.weathercode >= 51 && self.weather!.currentWeather.weathercode <= 99
        
        if isRaining {
            return [
                .init(color: .midnightEnd, location: 0),
                .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength),
                .init(color: .rainyEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength - 0.08),
                .init(color: .rainyEnd, location: (sunset - dayBegin)/dayLength),
                .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
                .init(color: .midnightEnd, location: 1)
            ]
        }
        
        return [
            .init(color: .midnightEnd, location: 0),
            .init(color: .midnightEnd, location: (sunrise - dayBegin)/dayLength - 0.08),
            .init(color: .sunriseEnd, location: (sunrise - dayBegin)/dayLength),
            .init(color: .sunnyDayEnd, location: (sunrise - dayBegin)/dayLength + 0.05),
            .init(color: .sunnyDayEnd, location: (sunset - dayBegin)/dayLength - 0.08),
            .init(color: .sunsetEnd, location: (sunset - dayBegin)/dayLength),
            .init(color: .midnightEnd, location: (sunset - dayBegin)/dayLength + 0.015),
            .init(color: .midnightEnd, location: 1)
        ]
    }
    
    func fetchCurrentPlacemark(coordinates: CLLocationCoordinate2D) {
        dispatchGroup.enter()
        
        let location = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location,completionHandler: {
            [self] (placemarks, error) in
            if error == nil {
                let firstLocation = placemarks?[0]
                self.placemark = firstLocation?.locality ?? ""
                dispatchGroup.leave()
            } else {
                print("Error fetching Coordinates")
                dispatchGroup.leave()
            }
        })
    }
    
    func fetchWeatherData(coordinates: CLLocationCoordinate2D) {
        dispatchGroup.enter()

        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(coordinates.latitude)&longitude=\(coordinates.longitude)&hourly=precipitation_probability,precipitation,windspeed_10m,uv_index&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&current_weather=true&forecast_days=1&timeformat=unixtime&timezone=auto") else { return }
                
        AF.request(url).validate().responseDecodable(of: OMDayTemperature.self) { response in
            switch response.result {
            case .success:
                self.weather = response.value
                let dayBegin = response.value!.hourly.time.first!
                self.time = (Date.now.timeIntervalSince1970-Double(dayBegin))/86400.0
                self.dispatchGroup.leave()
            case let .failure(error):
                print(error)
                self.dispatchGroup.leave()
            }
        }
    }
}
