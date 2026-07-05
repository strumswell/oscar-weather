import SwiftUI

struct ForecastDisplayModeOption: View {
  let mode: ForecastDaytimeTemperatureDisplayMode
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 6) {
          Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.top, 1)
          Text(mode.label)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(Color(UIColor.label))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
        }

        displayPreview
      }
      .padding(10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(UIColor.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var displayPreview: some View {
    switch mode {
    case .replaceValues:
      previewRow(
        labelLow: 13,
        labelHigh: 22,
        barLow: 13,
        barHigh: 22,
        focusLow: nil,
        focusHigh: nil,
        height: 8
      )
    case .overlayOnDailyRange:
      previewRow(
        labelLow: 8,
        labelHigh: 25,
        barLow: 8,
        barHigh: 25,
        focusLow: 13,
        focusHigh: 22,
        height: 28
      )
    }
  }

  private func previewRow(
    labelLow: Double,
    labelHigh: Double,
    barLow: Double,
    barHigh: Double,
    focusLow: Double?,
    focusHigh: Double?,
    height: CGFloat
  ) -> some View {
    HStack(spacing: 5) {
      Text(roundTemperatureString(temperature: labelLow))
        .font(.system(size: 13, weight: .medium))
        .frame(width: 26, alignment: .trailing)
        .offset(y: height > 8 ? 9 : 0)
      TemperatureRangeView(
        low: barLow,
        high: barHigh,
        focusLow: focusLow,
        focusHigh: focusHigh,
        minTemp: 6,
        maxTemp: 27,
        unit: "°C"
      )
      .frame(height: height)
      Text(roundTemperatureString(temperature: labelHigh))
        .font(.system(size: 13, weight: .medium))
        .frame(width: 26, alignment: .leading)
        .offset(y: height > 8 ? 9 : 0)
    }
  }
}
