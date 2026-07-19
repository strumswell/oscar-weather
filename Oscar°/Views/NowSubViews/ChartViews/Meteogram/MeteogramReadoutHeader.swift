import SwiftUI

/// House-style lollipop tooltip shown while scrubbing the meteogram —
/// the same idiom as the single-parameter charts.
struct MeteogramSelectionTooltip: View {
  let model: MeteogramModel
  let index: Int

  private var values: MeteogramModel.ReadoutValues {
    model.values(at: index)
  }

  var body: some View {
    VStack(alignment: .center, spacing: 2) {
      Text(verbatim: timeLabel(for: values.date))
        .font(.caption)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 1) {
        if let temperature = values.temperature {
          row(color: .orange, text: temperatureString(temperature))
        }
        if let pressure = values.pressure {
          row(color: .purple, text: pressureString(pressure))
        }
        if let speed = values.windSpeed {
          windRow(speed: speed, direction: values.windDirection)
        }
        if let gust = values.gust {
          row(color: .teal.opacity(0.5), text: windString(gust))
        }
        if let rain = values.rain, rain > 0 {
          row(color: .blue, text: precipitationString(rain))
        }
        if let snowfall = values.snowfall, snowfall > 0 {
          row(color: .cyan, text: snowString(snowfall))
        }
        if let probability = values.probability {
          row(color: .blue.opacity(0.45), text: percentString(probability))
        }
        if let cloud = values.cloudTotal {
          row(color: .white.opacity(0.7), text: percentString(cloud))
        }
      }
    }
    .padding(8)
    .background(.ultraThinMaterial.opacity(0.9))
    .clipShape(.rect(cornerRadius: 8))
    .shadow(radius: 4)
  }

  private func row(color: Color, text: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text(verbatim: text)
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.white)
    }
  }

  private func windRow(speed: Double, direction: Double?) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(.teal)
        .frame(width: 6, height: 6)
      if let direction {
        Image(systemName: "location.north.fill")
          .resizable()
          .frame(width: 8, height: 8)
          .rotationEffect(.degrees((direction + 180).truncatingRemainder(dividingBy: 360)))
          .foregroundStyle(.white)
      }
      Text(verbatim: windString(speed))
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.white)
    }
  }

  // MARK: - Formatting

  private func timeLabel(for date: Date) -> String {
    HourlyChartUtilities.dayAbbreviation(from: date) + " "
      + HourlyChartUtilities.timeString(from: date)
  }

  private func temperatureString(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) \(model.temperatureUnit)"
  }

  private func pressureString(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0)))) \(model.pressureUnit)"
  }

  private func windString(_ value: Double) -> String {
    WindSpeedFormatter.string(value, unit: model.windSpeedUnit.displayUnit)
  }

  private func precipitationString(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) \(model.precipitationUnit)"
  }

  private func snowString(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) cm"
  }

  private func percentString(_ value: Double) -> String {
    "\(Int(value.rounded())) %"
  }
}

/// Color legend under the charts, matching the legend style of the
/// single-parameter charts.
struct MeteogramLegend: View {
  private let columns = [GridItem(.adaptive(minimum: 92), alignment: .leading)]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
      item(color: .orange, label: "Temperatur")
      item(color: .purple.opacity(0.75), label: "Luftdruck")
      item(color: .teal, label: "Wind")
      item(color: .teal.opacity(0.4), label: "Böen")
      item(color: .blue, label: "Regen")
      item(color: .cyan, label: "Schnee")
      item(color: .white.opacity(0.7), label: "Bewölkung")
      item(color: .yellow.opacity(0.8), label: "Sonne")
    }
  }

  private func item(color: Color, label: LocalizedStringKey) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 7, height: 7)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}
