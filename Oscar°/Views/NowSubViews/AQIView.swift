//
//  AQIView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 19.12.22.
//

import SwiftUI

struct AQIView: View {
    @Environment(Weather.self) private var weather: Weather
    @State private var detailAnchor: EnvironmentDetailSection?

    private var metrics: [EnvironmentMetric] {
        let h = weather.air.hourly
        let time = h?.time ?? []
        let uvValue = environmentValue(from: h?.uv_index, time: time)
        let aqiValue = environmentValue(from: h?.european_aqi, time: time)
        let pm25Value = environmentValue(from: h?.european_aqi_pm2_5, time: time)
        let pm10Value = environmentValue(from: h?.european_aqi_pm10, time: time)
        let no2Value = environmentValue(from: h?.european_aqi_no2, time: time)
        let o3Value = environmentValue(from: h?.european_aqi_o3, time: time)
        let so2Value = environmentValue(from: h?.european_aqi_so2, time: time)
        let alderValue = environmentValue(from: h?.alder_pollen, time: time) ?? nil
        let birchValue = environmentValue(from: h?.birch_pollen, time: time) ?? nil
        let grassValue = environmentValue(from: h?.grass_pollen, time: time) ?? nil
        let mugwortValue = environmentValue(from: h?.mugwort_pollen, time: time) ?? nil
        let ragweedValue = environmentValue(from: h?.ragweed_pollen, time: time) ?? nil

        var all: [EnvironmentMetric] = [
            .forUV(value: uvValue),
            .forAQI(id: "aqi",  label: "AQI",  value: aqiValue),
            .forAQI(id: "pm25", label: "PM",   subscript_: "2.5", value: pm25Value),
            .forAQI(id: "pm10", label: "PM",   subscript_: "10",  value: pm10Value),
            .forAQI(id: "no2",  label: "NO",   subscript_: "2",   value: no2Value),
            .forAQI(id: "o3",   label: "O",    subscript_: "3",   value: o3Value),
            .forAQI(id: "so2",  label: "SO",   subscript_: "2",   value: so2Value),
        ]

        let pollen: [EnvironmentMetric] = [
            .forPollen(type: .alder,   label: "Erle",     value: alderValue),
            .forPollen(type: .birch,   label: "Birke",    value: birchValue),
            .forPollen(type: .grass,   label: "Gräser",   value: grassValue),
            .forPollen(type: .mugwort, label: "Beifuß",   value: mugwortValue),
            .forPollen(type: .ragweed, label: "Ambrosia", value: ragweedValue),
        ].compactMap { $0 }

        all.append(contentsOf: pollen)
        return all.sorted { $0.severityFraction > $1.severityFraction }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Umwelt")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
                .padding([.leading, .bottom])
                .padding(.top, 30)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(metrics) { metric in
                        Button(action: {
                            presentDetail(for: metric)
                        }) {
                            AQIGaugeCard(metric: metric)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accessibilityLabel(for: metric))
                        .accessibilityHint(Text("Öffnet stündliche Umweltdiagramme"))
                    }
                }
                .scrollTargetLayout()
                .font(.system(size: 18))
                .padding([.leading, .trailing])
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .opacity(weather.isLoading || weather.air.hourly == nil ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
        }
        .sheet(item: $detailAnchor, content: EnvironmentDetailView.init)
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }

    private func presentDetail(for metric: EnvironmentMetric) {
        detailAnchor = detailSection(for: metric)
    }

    private func detailSection(for metric: EnvironmentMetric) -> EnvironmentDetailSection {
        switch metric.id {
        case "uv":
            .uv
        case "aqi", "pm25", "pm10", "no2", "o3", "so2":
            .aqi
        default:
            .pollen
        }
    }

    private func accessibilityLabel(for metric: EnvironmentMetric) -> Text {
        if let subscriptLabel = metric.subscriptLabel {
            return Text("\(metric.label) \(subscriptLabel), \(Int(metric.rawValue))")
        }

        return Text("\(LocalizedStringKey(metric.label)), \(Int(metric.rawValue))")
    }
}
