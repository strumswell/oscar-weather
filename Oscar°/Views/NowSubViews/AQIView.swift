//
//  AQIView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 19.12.22.
//

import SwiftUI

struct AQIView: View {
    @Binding var aqi: AQIResponse?

    var body: some View {
        Text("Umwelt")
            .font(.title3)
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding([.leading, .bottom])
            .padding(.top, 30)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                VStack {
                    Text("UV")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.uvIndex[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.uvIndex[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForUVI(uvi: aqi?.hourly.uvIndex[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("AQI")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqi[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqi[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqi[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("PM")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    + Text("2.5")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqiPm25[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqiPm25[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqiPm25[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("PM")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    + Text("10")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqiPm10[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqiPm10[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqiPm10[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("NO")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    + Text("2")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqiNo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqiNo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqiNo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("O")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    + Text("3")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqiO3[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqiO3[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqiO3[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
                VStack {
                    Text("SO")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    + Text("2")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                    Gauge(value: max(100 - Double(aqi?.hourly.europeanAqiSo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0), 0), in:0...100) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    } currentValueLabel: {
                        Text("\(Int(aqi?.hourly.europeanAqiSo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))")
                            .foregroundColor(aqi?.hourly.getColorForAQI(aqi: aqi?.hourly.europeanAqiSo2[aqi?.hourly.getCurrentHour() ?? 0] ?? 0))

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
                .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
                .cornerRadius(10)
                
            }
            .font(.system(size: 18))
            .padding([.leading, .trailing])
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 20)
    }
}
