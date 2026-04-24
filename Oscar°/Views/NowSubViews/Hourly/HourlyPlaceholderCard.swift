import SwiftUI

struct HourlyPlaceholderCard: View {
  var body: some View {
    VStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 42, height: 12)
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 52, height: 9)
      Circle()
        .frame(width: 35, height: 35)
      RoundedRectangle(cornerRadius: 3)
        .frame(width: 30, height: 12)
    }
    .foregroundStyle(.secondary.opacity(0.28))
    .padding(.horizontal, 12)
    .padding(.vertical, 12)
    .frame(minWidth: 78, minHeight: 116)
    .background(.thinMaterial)
    .clipShape(.rect(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(.secondary.opacity(0.075), lineWidth: 1)
    }
    .redacted(reason: .placeholder)
    .accessibilityHidden(true)
  }
}
