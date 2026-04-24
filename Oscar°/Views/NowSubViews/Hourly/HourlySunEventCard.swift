import SwiftUI

struct HourlySunEventCard: View {
  let item: HourlySunEventItem

  var body: some View {
    VStack {
      Text(item.time)
        .foregroundStyle(.primary)
        .bold()
      Text(item.weekday)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.top, 3)
      Spacer()
      Image("halfsun")
        .resizable()
        .scaledToFit()
        .shadow(
          color: .orange,
          radius: 10,
          x: 0,
          y: -5
        )
        .frame(width: 45, height: 45)
        .padding(.bottom, -3)
        .accessibilityHidden(true)
      Image(systemName: item.kind.iconName)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .background(.thinMaterial)
    .clipShape(.rect(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}
