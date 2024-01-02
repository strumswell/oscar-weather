//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI
import Charts

struct RainView: View {
    @Binding var rain: RainRadarForecast?
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
        if (getMaxPreci() > 0) {
            Text("Radar")
                .font(.system(size: 20))
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .top])
            
                HStack {
                    VStack {
                        Text("\(getMaxPreci(), specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Spacer()
                        Text("\(getMaxPreci() / 2, specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Spacer()
                        Text("0 mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Text("")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                    }
                    VStack {
                        if (getMaxPreci() <= 1) {
                            Chart(data: weather.rain.data?.map{$0.mmh ?? 0} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                        LinearGradient(gradient: .init(colors: [Color.blue, Color.blue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        } else if ((weather.rain.data?.count ?? 0) > 0) {
                            Chart(data: weather.rain.data?.map{($0.mmh ?? 0) / getMaxPreci()} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                        LinearGradient(gradient: .init(colors: [Color.blue, Color.blue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        }
                        HStack() {
                            Text("\(getStartTime())")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.label))
                            Spacer()
                            if (weather.rain.data?.count ?? 0 > 1) {
                                Text("\(getMidTime())")
                                    .font(.footnote)
                                    .foregroundColor(Color(UIColor.label))
                                Spacer()
                            }
                            Text("\(getEndTime())")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.label))
                        }
                    }
                
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
            .cornerRadius(10)
            .font(.system(size: 18))
            .padding([.leading, .trailing, .bottom])
            .frame(height: 165)
        }
    }
}

extension RainView {
    public func getStartTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: weather.rain.data?.first?.time ?? "2022-01-01") ?? Date())
    }
    
    public func getMidTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: weather.rain.data?.middle?.time ?? "2022-01-01") ?? Date())
    }
    
    public func getFormattedTime(time: String) -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: time) ?? Date())
    }
    
    
    public func getEndTime() -> String {
        let iso = ISO8601DateFormatter()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: iso.date(from: weather.rain.data?.last?.time ?? "2022-01-01") ?? Date())
    }
    
    func getMaxPreci() -> Double {
        var maxPreci = 0.0
        for datapoint in weather.rain.data ?? [] {
            if (datapoint.mmh ?? 0 > maxPreci) {
                maxPreci = datapoint.mmh ?? 0
            }
        }
        
        if (maxPreci <= 1 && maxPreci > 0) {
            return 1
        }
        return maxPreci
    }
}
