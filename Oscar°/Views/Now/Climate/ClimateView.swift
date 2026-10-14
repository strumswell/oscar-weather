import SwiftUI
import UIKit

struct ClimateView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var model = ClimateModel()

    private var latitude: Double { weather.forecast.latitude ?? 0 }
    private var longitude: Double { weather.forecast.longitude ?? 0 }

    private var unit: ClimateTemperatureUnit {
        ClimateTemperatureUnit(settingValue: SettingService.resolvedTemperatureUnit)
    }

    private var todayHighCelsius: Double? {
        guard let high = weather.forecast.daily?.temperature_2m_max?.first else { return nil }
        return unit.celsius(fromValue: high)
    }

    private var loadIdentity: String {
        let coords = String(format: "%.2f,%.2f", latitude, longitude)
        let day = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let high = todayHighCelsius.map { String(Int($0.rounded())) } ?? "nil"
        return "\(coords)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(high)"
    }

    var body: some View {
        Group {
            if (latitude == 0 && longitude == 0) || model.phase == .failed {
                EmptyView()
            } else {
                VStack(alignment: .leading) {
                    NowSectionHeader(showMore: showDetail) {
                        Text("Klima")
                    }
                    .padding(.bottom)

                    content
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.8)
                        .scaleEffect(phase.isIdentity ? 1 : 0.99)
                }
            }
        }
        .task(id: loadIdentity) {
            await model.load(
                latitude: latitude, longitude: longitude,
                todayHigh: todayHighCelsius, identity: loadIdentity)
        }
        .task(id: weather.lastUpdated) {
            await model.load(
                latitude: latitude, longitude: longitude,
                todayHigh: todayHighCelsius, identity: loadIdentity)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let summary = model.summary, model.phase == .loaded {
            Button {
                presentDetail(summary)
            } label: {
                ClimateSummaryCard(summary: summary, unit: unit)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Klima. \(ClimateCopy.headline(summary)) \(ClimateCopy.statLine(summary, unit))"))
            .accessibilityHint(Text("Öffnet Klimadetails"))
            .accessibilityIdentifier("now.climate")
        } else {
            ClimatePlaceholder(isThrottled: model.phase == .throttled)
        }
    }

    private var showDetail: (() -> Void)? {
        guard let summary = model.summary, model.phase == .loaded else { return nil }
        return { presentDetail(summary) }
    }

    private func presentDetail(_ summary: ClimateSummary) {
        presentation.present(.climate(summary))
    }
}
