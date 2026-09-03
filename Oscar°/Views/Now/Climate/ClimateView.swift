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

    /// Today's forecast high, converted to °C to match the ERA5 history (the forecast comes back
    /// in the user's unit). Used as the live current-year point since ERA5 lags ~5 days.
    private var todayHighCelsius: Double? {
        guard let high = weather.forecast.daily?.temperature_2m_max?.first else { return nil }
        return unit.celsius(fromValue: high)
    }

    /// Recompute identity: changes when the location, the calendar day (midnight rollover → a new
    /// "this day"), or today's high changes — so the section never shows a stale day/value.
    private var loadIdentity: String {
        let coords = String(format: "%.2f,%.2f", latitude, longitude)
        let day = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let high = todayHighCelsius.map { String(Int($0.rounded())) } ?? "nil"
        return "\(coords)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(high)"
    }

    var body: some View {
        Group {
            if (latitude == 0 && longitude == 0) || model.phase == .failed {
                // No location yet, or the archive is unavailable for this spot: stay invisible
                // rather than leaving a broken-looking gap.
                EmptyView()
            } else {
                VStack(alignment: .leading) {
                    Text("Klima")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.primary)
                        .padding([.leading, .bottom])
                        .padding(.top, 30)

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
            // A weather refresh (incl. returning to foreground): retry if the section failed earlier
            // or is still on a previous day's data. Lifecycle-bound like the load above, and a no-op
            // when already current or in flight — so it never interrupts the expensive cold fetch
            // (which the primary task owns) and is cancelled with the view.
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

    private func presentDetail(_ summary: ClimateSummary) {
        Haptics.impact()
        presentation.present(.climate(summary))
    }
}
