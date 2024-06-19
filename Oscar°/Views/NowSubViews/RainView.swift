//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//
import SwiftUI
import Charts

struct RainView: View {
    @Environment(Weather.self) private var weather: Weather
    
    var body: some View {
        if weather.radar.isRaining() {
            VStack(alignment: .leading) {
                Text("Radar")
                    .font(.system(size: 20))
                    .bold()
                    .foregroundColor(Color(UIColor.label))
                    .padding([.leading, .top])
                Chart {
                    ForEach(weather.radar.radar ?? [], id: \.timestamp) { data in
                        if let timestamp = data.timestamp, let precipitation = data.precipitation_5?.first?.first {
                            AreaMark(
                                x: .value("Time", timestamp),
                                y: .value("Precipitation", Double(precipitation) / 10.0)
                            )
                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.2)]), startPoint: .top, endPoint: .bottom))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisTick()
                        AxisValueLabel() {
                            if let date = value.as(Date.self) {
                                Text(getFormattedTime(time: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    let yAxisValues = getYAxisValues()
                    AxisMarks(values: yAxisValues) { value in
                        AxisGridLine()
                        AxisValueLabel() {
                            if let value = value.as(Double.self) {
                                Text("\(value, specifier: "%.1f") mm/h") // Add "mm" to y-axis labels
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(.thinMaterial)
                .cornerRadius(10)
                .padding([.leading, .trailing, .bottom])
                .frame(height: 180)
            }
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(phase.isIdentity ? 1 : 0.99)
                    .blur(radius: phase.isIdentity ? 0 : 0.5)
            }
        }
    }
    
    func getFormattedTime(time: Date?) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time ?? Date())
    }
    
    func getMaxPreci() -> Double {
        let maxPreci = weather.radar.radar?.compactMap { Double($0.precipitation_5?.first?.first ?? 0) / 10 }.max() ?? 0
        return maxPreci < 1 ? 1 : maxPreci
    }
    
    func getYAxisValues() -> [Double] {
        let maxPreci = getMaxPreci()
        return [0, maxPreci / 2, maxPreci]
    }
}
