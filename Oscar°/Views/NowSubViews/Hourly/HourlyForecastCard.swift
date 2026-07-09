import SwiftUI

struct HourlyForecastCard: View {
  let item: HourlyForecastItem
  /// One width for every card in the hourly strip (forecast, sun event,
  /// placeholder), so the row reads as an even rhythm.
  static let cardWidth: CGFloat = 82
  @Environment(\.cardBackgroundStyle) private var cardBackground

  var body: some View {
    VStack {
      Text(item.hour)
        .bold()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(item.precipitation)
        .font(.footnote)
        .foregroundStyle(.secondary)
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
    .background(cardBackground)
    .clipShape(.rect(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.secondary.opacity(0.075), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}
