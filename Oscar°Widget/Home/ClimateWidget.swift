// Warming stripes for today's calendar day, read only from the app's climate archive cache.
import SwiftUI
import WidgetKit

struct ClimateEntry: TimelineEntry {
    let date: Date
    let location: String
    let summary: ClimateSummary?
    var cityID: String? = nil
}

struct ClimateProvider: PlaceTimelineSource {
    var refreshMinutes: Int {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now)
        let untilTomorrow = Int(tomorrow.timeIntervalSinceNow / 60) + 5
        return min(180, max(5, untilTomorrow))
    }

    func placeholder(in context: Context) -> ClimateEntry {
        ClimateEntry(date: .now, location: "Leipzig", summary: .preview)
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [ClimateEntry] {
        let (weather, _) = try await WidgetForecast.forecast(place.coordinates)
        guard let todayHigh = weather.daily?.temperature_2m_max?[safe: weather.dayIndex(at: .now)],
              let latitude = weather.latitude,
              let longitude = weather.longitude else {
            throw URLError(.cannotParseResponse)
        }
        let summary = ClimateArchiveStore.cachedSummary(
            latitude: latitude,
            longitude: longitude,
            today: .now,
            todayHigh: todayHigh
        )
        let location = await place.locationName()
        return [ClimateEntry(date: .now, location: location, summary: summary, cityID: place.cityID)]
    }
}

struct ClimateWidgetView: View {
    let entry: ClimateEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let summary = entry.summary {
                    ClimateStripes(
                        stripes: summary.allStripes,
                        sigma: summary.standardDeviation,
                        monochrome: renderingMode == .accented
                    )
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(headline)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption + ". " + headline)
        .containerBackground(Color.midnightStart, for: .widget)
        .widgetURL(.oscarPlace(entry.cityID))
    }

    private var caption: String {
        guard let summary = entry.summary else { return entry.location }
        let firstYear = String(summary.firstYear)
        return String(localized: "\(entry.location) · \(summary.dayLabel) · \(firstYear) bis heute")
    }

    private var headline: String {
        guard let summary = entry.summary else {
            return String(localized: "Öffne den Ort einmal in Oscar°, um die Klimadaten zu laden.")
        }
        return ClimateCopy.headline(summary)
    }
}

struct ClimateStripes: View {
    let stripes: [ClimateStripe]
    let sigma: Double
    let monochrome: Bool

    var body: some View {
        Canvas { context, size in
            guard !stripes.isEmpty else { return }
            let width = size.width / CGFloat(stripes.count)
            for (index, stripe) in stripes.enumerated() {
                let rect = CGRect(x: CGFloat(index) * width, y: 0, width: width + 0.75, height: size.height)
                context.fill(Path(rect), with: .color(color(for: stripe)))
            }
        }
    }

    private func color(for stripe: ClimateStripe) -> Color {
        guard monochrome else {
            return ClimateStripeColor.color(anomaly: stripe.anomaly, sigma: sigma)
        }
        let scaled = stripe.anomaly / max(sigma, 0.001) / ClimateStripeColor.fullScaleSigma
        return .white.opacity(0.45 + 0.45 * min(max(scaled, -1), 1))
    }
}

struct ClimateWidget: Widget {
    let kind: String = "ClimateWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: ClimateProvider()) { entry in
            ClimateWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Klima"))
        .description(String(localized: "Der heutige Tag im Vergleich mit allen Jahren seit 1940."))
        .supportedFamilies([.systemMedium])
    }
}

extension ClimateSummary {
    static var preview: ClimateSummary? {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let years = Array(1940..<calendar.component(.year, from: now))
        let time = years.map { String(format: "%04d-%02d-%02d", $0, month, day) }
        let tmax: [Double?] = years.map { 8 + Double($0 - 1940) * 0.04 + 2.5 * sin(Double($0) * 1.7) }
        return make(time: time, tmax: tmax, referenceDate: now, todayOverride: 12)
    }
}

#Preview(as: .systemMedium) {
    ClimateWidget()
} timeline: {
    ClimateEntry(date: .now, location: "Leipzig", summary: .preview)
    ClimateEntry(date: .now, location: "Leipzig", summary: nil)
}
