import SwiftUI

/// Compact five-day block built from the real temperature-range bars.
struct CollageDailyCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(OnboardingSampleData.dailyRows) { row in
                HStack(spacing: 8) {
                    Text(row.weekday)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 42, alignment: .leading)
                    Image(row.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text(verbatim: "\(Int(row.low))°")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TemperatureRangeView(
                        low: row.low,
                        high: row.high,
                        focusLow: nil,
                        focusHigh: nil,
                        minTemp: OnboardingSampleData.dailyTemperatureBounds.min,
                        maxTemp: OnboardingSampleData.dailyTemperatureBounds.max,
                        unit: "°C"
                    )
                    .frame(height: 5)
                    Text(verbatim: "\(Int(row.high))°")
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(stagedCardFill)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.075), lineWidth: 1)
        }
    }
}

/// Warming stripes with a small title, like the Klima section's ribbon.
struct CollageClimateCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dieser Tag seit 1940")
                .font(.footnote.weight(.semibold))
            WarmingStripesRibbon(
                stripes: OnboardingSampleData.climateStripes,
                sigma: 1.0,
                height: 40
            )
        }
        .padding(14)
        .background(stagedCardFill)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}
