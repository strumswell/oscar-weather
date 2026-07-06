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
      Image(item.kind.imageName)
        .resizable()
        .scaledToFit()
        .frame(width: 45, height: 45)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .background(.thinMaterial)
    .clipShape(.rect(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }
}
