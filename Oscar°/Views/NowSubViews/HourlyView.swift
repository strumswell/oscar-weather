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
    
    var body: some View {
        Text("Stündlich")
            .font(.title3)
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding(.leading)
            .padding(.bottom, -10)
            .padding(.top)
        
        ScrollView(.horizontal, showsIndicators: false) {
            
            if ((weather.forecast.hourly == nil)) {
                ProgressView()
                    .padding()
            } else {
                HStack(spacing: 14) {
                    ForEach(self.getCurrentHour() ... self.getCurrentHour() + 48, id: \.self) { index in
                        VStack {
                            Text(self.getHourString(timestamp: weather.forecast.hourly?.time[index] ?? 0) + " Uhr")
                                .foregroundColor(Color(UIColor.label))
                                .bold()
                            Text("\(weather.forecast.hourly?.precipitation?[index] ?? 0, specifier: "%.1f") mm")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.label))
                                .padding(.top, 3)
                            Text("\(weather.forecast.hourly?.precipitation_probability?[index] ?? 0, specifier: "%.0f") %")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                            Image(self.getWeatherIcon(
                                weathercode: self.weather.forecast.hourly?.weathercode?[index] ?? 0,
                                isDay: self.weather.forecast.hourly?.is_day?[index] ?? 0))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 35, height: 35)
                            Text("\(weather.forecast.hourly?.temperature_2m?[index].rounded() ?? 0, specifier: "%.0f")°")
                                .foregroundColor(Color(UIColor.label))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                        .cornerRadius(10)
                    }
                    .padding(.vertical, 20)
                    
                }
                .font(.system(size: 18))
                .padding(.leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension View {
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
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: date)
        return String(format:"%02d", hours)
    }
}

