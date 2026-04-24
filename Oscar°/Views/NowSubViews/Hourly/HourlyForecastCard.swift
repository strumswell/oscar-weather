import SwiftUI

struct HourlyForecastCard: View {
  let item: HourlyForecastItem

  var body: some View {
    VStack {
      Text(item.hour)
        .bold()
      Text(item.precipitation)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 3)
        .contentTransition(.numericText())
      Image(item.iconName)
        .resizable()
        .scaledToFit()
        .frame(width: 35, height: 35)
        .accessibilityHidden(true)
      Text(item.temperature)
        .contentTransition(.numericText())
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .background(.thinMaterial)
    .clipShape(.rect(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.secondary.opacity(0.075), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
