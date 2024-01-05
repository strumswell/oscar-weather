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
        if getMaxPreci() > 0 {
            VStack(alignment: .leading) {
                headerView
                chartView
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(10)
                    .font(.system(size: 18))
                    .padding([.leading, .trailing, .bottom])
                    .frame(height: 165)
            }
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.8)
                    .scaleEffect(phase.isIdentity ? 1 : 0.99)
                    .blur(radius: phase.isIdentity ? 0 : 0.5)
            }
        }
    }
}

private extension RainView {
    var headerView: some View {
        Text("Radar")
            .font(.system(size: 20))
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding([.leading, .top])
    }
    
    var chartView: some View {
        HStack {
            precipitationScale
            VStack {
                chart
                timeLabels
            }
        }
    }
    
    var precipitationScale: some View {
        VStack {
            Text("\(getMaxPreci(), specifier: "%.1f") mm/h")
            Spacer()
            Text("\(getMaxPreci() / 2, specifier: "%.1f") mm/h")
            Spacer()
            Text("0 mm/h")
        }
        .font(.footnote)
        .foregroundColor(Color(UIColor.label))
    }
    
    var chart: some View {
        VStack {
            if getMaxPreci() <= 1 {
                Chart(data: getRadarForecast())
                    .chartStyle(
                        AreaChartStyle(.quadCurve, fill: blueGradient)
                    )
            } else if let radarCount = weather.radar.radar?.count, radarCount > 0 {
                Chart(data: weather.radar.radar?.map { (Double($0.precipitation_5?.first?.first ?? 0) / 10) / getMaxPreci() } ?? [])
                    .chartStyle(
                        AreaChartStyle(.quadCurve, fill: blueGradient)
                    )
            }
        }
    }
    
    var timeLabels: some View {
        HStack {
            Text(getFormattedTime(time: weather.radar.radar?.first?.timestamp))
            Spacer()
            if weather.radar.radar?.count ?? 0 > 1 {
                Text(getFormattedTime(time: weather.radar.radar?.middle?.timestamp))
                Spacer()
            }
            Text(getFormattedTime(time: weather.radar.radar?.last?.timestamp))
        }
        .font(.footnote)
        .foregroundColor(Color(UIColor.label))
    }

    var blueGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
    }

    func getFormattedTime(time: Date?) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time ?? Date())
    }
    
    func getMaxPreci() -> Double {
        let maxPreci = weather.radar.radar?.compactMap { Double($0.precipitation_5?.first?.first ?? 0) / 10 }.max() ?? 0
        return maxPreci <= 1 && maxPreci > 0 ? 1 : maxPreci
    }
    
    func getRadarForecast() -> [Double] {
        guard let radarEntries = weather.radar.radar else { return [] }
        return radarEntries.flatMap { entry in
            entry.precipitation_5?.flatMap { $0.map { Double($0) / 10.0 } } ?? []
        }
    }
}
