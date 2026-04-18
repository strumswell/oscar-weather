import SwiftUI

struct EnvironmentAirQualitySectionView: View {
    let currentAQI: Double?
    let currentAQIBadge: String
    let currentAQIColor: Color
    let aqiComponents: [AQIComponentSnapshot]
    let mainPollutant: AQIComponentSnapshot?
    let time: [Double]
    let aqi: [Double]
    let pm25: [Double]
    let pm10: [Double]
    let no2: [Double]
    let o3: [Double]
    let so2: [Double]
    let maxTimeRange: ClosedRange<Date>
    let referenceDate: Date
    @Binding var chartScrollPosition: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EnvironmentDetailCard {
                EnvironmentDetailHeaderView(
                    title: "Luftqualität",
                    value: currentAQI.map { String(Int($0)) } ?? "--",
                    badge: currentAQIBadge,
                    color: currentAQIColor,
                    subtitle: nil
                )

                AQIChart(
                    aqi: aqi,
                    pm25: pm25,
                    pm10: pm10,
                    no2: no2,
                    o3: o3,
                    so2: so2,
                    time: time,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .chartScrollPosition(x: $chartScrollPosition)
            }

            EnvironmentDetailCard {
                Text("Hauptschadstoff")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let mainPollutant {
                    Text(verbatim: mainPollutant.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(mainPollutant.accentColor)

                    Text("Aktuell dominierender Schadstoff")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(LocalizedStringKey(mainPollutant.explanationBodyKey))
                        .font(.body)
                        .foregroundStyle(.primary)
                } else {
                    EnvironmentDetailEmptyStateView(
                        title: "Keine Daten",
                        message: "Für die aktuelle Stunde liegen keine Luftqualitätsdaten vor."
                    )
                }
            }

            EnvironmentDetailCard {
                Text("Schadstoffe jetzt")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(Array(aqiComponents.enumerated()), id: \.element.id) { index, component in
                    if index > 0 {
                        Divider().overlay(.white.opacity(0.08))
                    }

                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(component.status))
                                .fontWeight(.semibold)
                                .foregroundStyle(component.statusColor)
                        }
                    } label: {
                        Text(verbatim: component.label)
                    }
                }
            }
        }
    }
}
