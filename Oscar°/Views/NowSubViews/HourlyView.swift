//
//  HourlyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI
import Charts

struct HourlyView: View {
    @Environment(Weather.self) private var weather: Weather
    @State private var showDetailView: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Stündlich")
                .font(.title3)
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding(.leading)
                .padding(.bottom, -10)
                .padding(.top)
            
            ScrollView(.horizontal, showsIndicators: false) {
                if weather.isLoading && weather.forecast.hourly == nil {
                    HStack(spacing: 12) {
                        ForEach((1...5).reversed(), id: \.self) {_ in
                            ProgressView()
                                .frame(width: 55, height: 140)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(.thinMaterial)
                                .cornerRadius(10)
                                .scrollTransition { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.5)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                        .blur(radius: phase.isIdentity ? 0 : 2)
                                }
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(.leading)
                    .padding(.top, 7)
                } else {
                    LazyHStack(spacing: 12) {
                        ForEach(getLocalizedHourIndex() ... getLocalizedHourIndex() + 48, id: \.self) { index in
                            VStack {
                                Text(getHourString(timestamp: weather.forecast.hourly?.time[index] ?? 0))
                                    .foregroundColor(Color(UIColor.label))
                                    .bold()
                                Text("\(weather.forecast.hourly?.precipitation?[index] ?? 0, specifier: "%.1f") mm")
                                    .font(.footnote)
                                    .foregroundColor(Color(UIColor.label))
                                    .padding(.top, 3)
                                Text("\(weather.forecast.hourly?.precipitation_probability?[index] ?? 0, specifier: "%.0f") %")
                                    .font(.footnote)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                Image(getWeatherIcon(
                                    weathercode: weather.forecast.hourly?.weathercode?[index] ?? 0,
                                    isDay: weather.forecast.hourly?.is_day?[index] ?? 0))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 35, height: 35)
                                Text(roundTemperatureString(temperature: weather.forecast.hourly?.temperature_2m?[index]))
                                    .foregroundColor(Color(UIColor.label))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(.thinMaterial)
                            .cornerRadius(10)
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.5)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                    .blur(radius: phase.isIdentity ? 0 : 2)
                            }
                            SunsetSunriseCard(index: index)
                                .scrollTransition { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.5)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                        .blur(radius: phase.isIdentity ? 0 : 2)
                                }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollTargetLayout()
                    .font(.system(size: 18))
                    .padding(.leading)
                }
                
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(maxWidth: .infinity)
        }
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            showDetailView.toggle()        }
        .sheet(isPresented: $showDetailView) {
            HourlyDetailView()
        }
    }
}

extension HourlyView {
    public func getLocalizedHourIndex() -> Int {
        let currentUnixTime = weather.forecast.current?.time ?? 0
        let hours = weather.forecast.hourly?.time ?? []
        
        // Initialize variables to track the closest time and its index
        var closestTime = Double.greatestFiniteMagnitude
        var closestIndex = -1
        
        for (index, time) in hours.enumerated() {
            // Check the absolute difference between current time and each time in the array
            let difference = abs(currentUnixTime - time)
            if difference < closestTime {
                closestTime = difference
                closestIndex = index
            }
        }
        
        // Check if a closest time was found
        if closestIndex != -1 {
            return closestIndex
        } else {
            return 0
        }
    }
    
    public func getWeatherIcon(weathercode: Double, isDay: Double) -> String {
        if (isDay > 0) {
            switch weathercode {
            case 0, 1:
                return "01d"
            case 2:
                return "02d"
            case 3:
                return "04d"
            case 45, 48:
                return "50d"
            case 51:
                return "10d"
            case 71, 73, 75, 77:
                return "13d"
            case 95, 96, 99:
                return "11d"
            default:
                return "09d"
            }
        } else {
            switch weathercode {
            case 0, 1:
                return "01n"
            case 2:
                return "02n"
            case 3:
                return "04n"
            case 45, 48:
                return "50n"
            case 51:
                return "10n"
            case 71, 73, 75, 77:
                return "13n"
            case 95, 96, 99:
                return "11n"
            default:
                return "09n"
            }
        }
    }
    
    public func getHourString(timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        let hours = calendar.component(.hour, from: date)
        return String(format:"%02d %@", hours, String(localized: "Uhr")).trimmingCharacters(in: .whitespaces)
    }
    
    func isWithinHourOfInterest(eventTimestamp: Int, referenceHour: Int) -> Bool {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(eventTimestamp))
        let referenceDate = Date(timeIntervalSince1970: TimeInterval(referenceHour))
        let calendar = Calendar.current
        let eventHour = calendar.component(.hour, from: eventDate)
        let referenceHour = calendar.component(.hour, from: referenceDate)
        
        return eventHour == referenceHour
    }
    
    func getDayIndexForHourlyForecast(hourlyTimestamp: Int) -> Int {
        let hourlyDate = Date(timeIntervalSince1970: TimeInterval(hourlyTimestamp))
        let calendar = Calendar.current
        for (index, sunriseTimestamp) in (weather.forecast.daily?.sunrise ?? []).enumerated() {
            let sunriseDate = Date(timeIntervalSince1970: TimeInterval(sunriseTimestamp))
            if calendar.isDate(hourlyDate, inSameDayAs: sunriseDate) {
                return index
            }
        }
        return 0 // Default to first day if no match found
    }
}

struct SunsetSunriseCard: View {
    @Environment(Weather.self) private var weather: Weather
    var index: Int
    
    var body: some View {
        let hourlyTimestamp = weather.forecast.hourly?.time[index] ?? 0
        let dayIndex = getDayIndexForHourlyForecast(hourlyTimestamp: hourlyTimestamp)
        
        if isWithinHourOfInterest(eventTimestamp: hourlyTimestamp, referenceHour: weather.forecast.daily?.sunrise?[dayIndex] ?? 0) {
            VStack {
                Text(getTimeString(timestamp: weather.forecast.daily?.sunrise?[dayIndex] ?? 0))
                    .foregroundColor(Color(UIColor.label))
                    .bold()
                Text(getWeekDay(timestamp: weather.forecast.daily?.sunrise?[dayIndex] ?? 0))
                    .foregroundColor(Color(UIColor.label))
                    .font(.footnote)
                    .padding(.top, 3)
                Spacer()
                Image("halfsun")
                    .resizable()
                    .scaledToFit()
                    .shadow(
                        color: .orange,
                        radius: CGFloat(10),
                        x: CGFloat(0), y: CGFloat(-5))
                    .frame(width: 50, height: 50)
                    .padding(.bottom, -3)
                Image(systemName: "arrow.up")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.thinMaterial)
            .cornerRadius(10)
        } else if isWithinHourOfInterest(eventTimestamp: hourlyTimestamp, referenceHour: weather.forecast.daily?.sunset?[dayIndex] ?? 0) {
            VStack {
                Text(getTimeString(timestamp: weather.forecast.daily?.sunset?[dayIndex] ?? 0))
                    .foregroundColor(Color(UIColor.label))
                    .bold()
                Text(getWeekDay(timestamp: weather.forecast.daily?.sunset?[dayIndex] ?? 0))
                    .foregroundColor(Color(UIColor.label))
                    .font(.footnote)
                    .padding(.top, 3)
                Spacer()
                Image("halfsun")
                    .resizable()
                    .scaledToFit()
                    .shadow(
                        color: .orange,
                        radius: CGFloat(10),
                        x: CGFloat(0), y: CGFloat(-5))
                    .frame(width: 50, height: 50)
                    .padding(.bottom, -3)
                Image(systemName: "arrow.down")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.thinMaterial)
            .cornerRadius(10)
        }
    }
}

extension SunsetSunriseCard {
    func isWithinHourOfInterest(eventTimestamp: Double, referenceHour: Double) -> Bool {
        let eventDate = Date(timeIntervalSince1970: TimeInterval(eventTimestamp))
        let referenceDate = Date(timeIntervalSince1970: TimeInterval(referenceHour))
        let calendar = Calendar.current
        let eventHour = calendar.component(.hour, from: eventDate)
        let referenceHour = calendar.component(.hour, from: referenceDate)
        
        return eventHour == referenceHour
    }
    
    func getDayIndexForHourlyForecast(hourlyTimestamp: Double) -> Int {
        let hourlyDate = Date(timeIntervalSince1970: TimeInterval(hourlyTimestamp))
        let calendar = Calendar.current
        for (index, sunriseTimestamp) in (weather.forecast.daily?.sunrise ?? []).enumerated() {
            let sunriseDate = Date(timeIntervalSince1970: TimeInterval(sunriseTimestamp))
            if calendar.isDate(hourlyDate, inSameDayAs: sunriseDate) {
                return index
            }
        }
        return 0 // Default to first day if no match found
    }
    
    public func getTimeString(timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        let hours = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        return String(format:"%02d:%02d", hours, minutes)
    }
    
    public func getWeekDay(timestamp: Double) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

