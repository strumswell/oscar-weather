import SwiftUI

struct HourlySunEventCard: View {
  let item: HourlySunEventItem
  @Environment(\.cardBackgroundStyle) private var cardBackground

  var body: some View {
    VStack {
      Text(item.time)
        .foregroundStyle(.primary)
        .bold()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(item.weekday)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 3)
      // Same level as the forecast cards' weather icons — not pinned to the
      // card's bottom edge. Drawn a tad larger than its 35pt layout slot so
      // the card heights across the strip still match exactly.
      Image(item.kind.imageName)
        .resizable()
        .scaledToFit()
        .frame(width: 45, height: 45)
        .frame(width: 35, height: 35)
        .padding(.top, 1)
        .accessibilityHidden(true)
      // Invisible stand-in for the forecast cards' temperature line, so both
      // card types share one natural height at any type size.
      Text(verbatim: "0°")
        .hidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(width: HourlyForecastCard.cardWidth)
    .background(cardBackground)
    .clipShape(.rect(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}
