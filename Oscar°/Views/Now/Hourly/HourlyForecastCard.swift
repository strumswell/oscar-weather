import SwiftUI

struct HourlyForecastCard: View {
  let item: HourlyForecastItem
  static let cardWidth: CGFloat = 82

  var body: some View {
    VStack {
      Text(item.hour)
        .bold()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(item.precipitation)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.72))
        .padding(.top, 3)
      Image(item.iconName)
        .resizable()
        .scaledToFit()
        .frame(width: 35, height: 35)
        .accessibilityHidden(true)
      Text(item.temperature)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(width: Self.cardWidth)
    .cardBackground()
    .clipShape(.rect(cornerRadius: 10))
    .cardBorder()
    .accessibilityElement(children: .combine)
  }
}
