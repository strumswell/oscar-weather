//
//  AQIView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 19.12.22.
//

import SwiftUI

struct AQIView: View {
    @Environment(Weather.self) private var weather: Weather
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Umwelt")
                .font(.title3)
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .bottom])
                .padding(.top, 30)
            if ((weather.air.hourly == nil)) {
                ProgressView()
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        VStack {
                            Text("UV")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.uv_index?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.uv_index?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForUVI(uvi: weather.air.hourly?.uv_index?[getCurrentHour()] ?? 0))
                            } minimumValueLabel: {
                                Text("\(Int(11))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        
                        VStack {
                            Text("AQI")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.8)
                                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                                .blur(radius: phase.isIdentity ? 0 : 0.5)
                        }
                        
                        VStack {
                            Text("PM")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            + Text("2.5")
                                .font(.system(size: 12))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi_pm2_5?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi_pm2_5?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi_pm2_5?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        
                        VStack {
                            Text("PM")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            + Text("10")
                                .font(.system(size: 12))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi_pm10?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi_pm10?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi_pm10?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        
                        VStack {
                            Text("NO")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            + Text("2")
                                .font(.system(size: 12))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi_no2?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi_no2?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi_no2?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        
                        VStack {
                            Text("O")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            + Text("3")
                                .font(.system(size: 12))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi_o3?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi_o3?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi_o3?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                        
                        VStack {
                            Text("SO")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            + Text("2")
                                .font(.system(size: 12))
                                .fontWeight(.semibold)
                                .foregroundColor(Color(UIColor.label))
                            Gauge(value: max(100 - Double(weather.air.hourly?.european_aqi_so2?[getCurrentHour()] ?? 0), 0), in:0...100) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } currentValueLabel: {
                                Text("\(Int(weather.air.hourly?.european_aqi_so2?[getCurrentHour()] ?? 0))")
                                    .foregroundColor(getColorForAQI(aqi: Int(weather.air.hourly?.european_aqi_so2?[getCurrentHour()] ?? 0)))
                            } minimumValueLabel: {
                                Text("\(Int(100))")
                                    .foregroundColor(Color.purple)
                            } maximumValueLabel: {
                                Text("\(Int(0))")
                                    .foregroundColor(Color.green)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.purple, .red, .orange, .yellow, .green]))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                        .cornerRadius(10)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .blur(radius: phase.isIdentity ? 0 : 2)
                        }
                    }
                    .scrollTargetLayout()
                    .font(.system(size: 18))
                    .padding([.leading, .trailing])
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
            }
        }
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }
}

extension AQIView {
    public func getCurrentHour() -> Int {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: now)
        return components.hour!
    }
    
    public func getColorForAQI(aqi: Int) -> Color {
        switch aqi {
        case let x where x <= 20:
            return .green
        case let x where x > 20 && x <= 40:
            return .orange
        case let x where x > 40 && x <= 60:
            return .orange
        case let x where x > 60 && x <= 80:
            return .red
        case let x where x > 80:
            return .purple
        default:
            return .gray
        }
    }
    
    public func getColorForUVI(uvi: Double) -> Color {
        switch uvi {
        case let x where x < 1:
            return .green
        case let x where x >= 1 && x < 2.5:
            return .green
        case let x where x >= 2.5 && x < 5.5:
            return .orange
        case let x where x >= 5.5 && x < 7.5:
            return .orange
        case let x where x >= 7.5 && x < 10.5:
            return .orange
        case let x where x >= 10.5:
            return .purple
        default:
            return .gray
        }
    }
}
