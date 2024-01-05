//
//  DailyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct DailyView: View {
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        VStack(alignment: .leading) {
            Text("10-Tage")
                .font(.title3)
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .top, .bottom])
            HStack {
                
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(0...9, id: \.self) { dayPos in
                        Text(getWeekDay(timestamp: weather.forecast.daily?.time[dayPos] ?? 0.0) )
                            .foregroundColor(Color(UIColor.label))
                    }
                }
                .padding(.leading)
                Spacer()
                VStack(spacing: 14) {
                    ForEach(0...9, id: \.self) { dayPos in
                        Image(getWeatherIcon(pos: dayPos))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                    }
                }
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(0...9, id: \.self) { dayPos in
                        VStack {
                            Text("\(weather.forecast.daily?.precipitation_sum?[dayPos] ?? 0, specifier: "%.1f") mm")
                                .font(.caption)
                                .foregroundColor(Color(UIColor.label))
                            Text("\(weather.forecast.daily?.precipitation_probability_max?[dayPos] ?? 0, specifier: "%.0f") %")
                                .font(.caption)
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 22) {
                    ForEach(0...9, id: \.self) { dayPos in
                        Text("\(weather.forecast.daily?.temperature_2m_max?[dayPos].rounded() ?? 0, specifier: "%.0f")°")
                            .fontWeight(.semibold)
                            .foregroundColor(Color(UIColor.label))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 22) {
                    ForEach(0...9, id: \.self) { dayPos in
                        Text("\(weather.forecast.daily?.temperature_2m_min?[dayPos].rounded() ?? 0, specifier: "%.0f")°")
                            .fontWeight(.light)
                            .foregroundColor(Color(UIColor.label))
                    }
                }
                .padding(.trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
            .cornerRadius(10)
            .font(.system(size: 18))
            .padding([.leading, .trailing])
        }
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }
}

extension DailyView {
    public func getWeekDay(timestamp: Double) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC\(String(describing: weather.forecast.timezone_abbreviation))")
        dateFormatter.dateFormat = "EEEE"
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
    
    public func getWeatherIcon(pos: Int) -> String {
        switch weather.forecast.daily?.weathercode?[pos] {
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
    }
}
