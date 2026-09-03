import SwiftUI

struct DailyDetailChartCard<Content: View>: View {
  let title: LocalizedStringKey
  let color: Color
  let isLoading: Bool
  private let content: Content

  init(
    title: LocalizedStringKey,
    color: Color,
    isLoading: Bool,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.color = color
    self.isLoading = isLoading
    self.content = content()
  }

  var body: some View {
    DetailCard {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ZStack {
        content
      }
    }
    .accessibilityElement(children: .contain)
  }
}

struct DailyDetailLoadingChart: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.secondary.opacity(0.08))
      ProgressView()
    }
    .frame(height: 220)
  }
}
