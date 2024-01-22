//
//  LockscreenProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit
import Alamofire

struct TemperatureLockScreenEntry: TimelineEntry {
    let date: Date
    let temperatureMin: Double
    let temperatureMax: Double
    let temperatureNow: Double
    let icon: String
    let precipitation: Double
    let precipitationProbability: Int
}

struct LockscreenProvider: TimelineProvider {
    var lm: LocationManager
    let defaultCoordinate = CLLocationCoordinate2D.init(latitude: 52.42, longitude: 12.52)

    init() {
        lm = LocationManager()
        lm.update()
    }


    func placeholder(in context: Context) -> TemperatureLockScreenEntry {
        TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TemperatureLockScreenEntry) -> ()) {
        let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: 0, temperatureMax: 22, temperatureNow: 10, icon: "cloud.fill", precipitation: 2.5, precipitationProbability: 72)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureLockScreenEntry>) -> ()) {
        lm.update()
        let currentDate = Date()
        let coordinate = lm.gpsLocation ?? self.defaultCoordinate
        
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&hourly=precipitation_probability,precipitation,windspeed_10m,uv_index&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset&current_weather=true&forecast_days=1&timeformat=unixtime&timezone=auto") else { return }
        
        AF.request(url).validate().responseDecodable(of: OMDayTemperature.self) { response in
            switch response.result {
            case .success:
                let entry = TemperatureLockScreenEntry(date: Date(), temperatureMin: response.value!.daily.temperature2MMin.first!, temperatureMax: response.value!.daily.temperature2MMax.first!, temperatureNow: response.value!.currentWeather.temperature, icon: response.value!.currentWeather.getWeatherIcon(), precipitation: response.value!.hourly.precipitation.first!, precipitationProbability: response.value!.hourly.precipitationProbability.first!)
                let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
                let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
                completion(timeline)
            case let .failure(error):
                print(error)
            }
        }
        
    }
}
