import Charts
import SwiftUI

/// The scaffold the three ensemble charts share: day-tick x axis, a seven-day
/// scroll window for long ranges, the selection binding, the bottom legend,
/// scroll reset when the data changes, and one VoiceOver summary for the whole
/// chart instead of a hundred auto-generated mark elements.
struct DailyEnsembleChartShell<Content: ChartContent, Legend: View>: View {
  let points: [DailyEnsembleDayPoint]
  @Binding var selectedDate: Date?
  let domainPadding: TimeInterval
  let yDomain: ClosedRange<Double>?
  let height: CGFloat
  let accessibilityLabel: LocalizedStringKey
  let accessibilityValue: String
  let legend: Legend
  let content: Content

  @State private var scrollPosition = Date.now

  init(
    points: [DailyEnsembleDayPoint],
    selectedDate: Binding<Date?>,
    domainPadding: TimeInterval = 0,
    yDomain: ClosedRange<Double>? = nil,
    height: CGFloat,
    accessibilityLabel: LocalizedStringKey,
    accessibilityValue: String,
    @ViewBuilder legend: () -> Legend,
    @ChartContentBuilder content: () -> Content
  ) {
    self.points = points
    self._selectedDate = selectedDate
    self.domainPadding = domainPadding
    self.yDomain = yDomain
    self.height = height
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityValue = accessibilityValue
    self.legend = legend()
    self.content = content()
  }

  var body: some View {
    Chart {
      content
    }
    .chartXAxis {
      AxisMarks(values: points.map(\.date)) { _ in
        AxisValueLabel(format: .dateTime.weekday(.narrow).day())
        AxisGridLine()
        AxisTick()
      }
    }
    .chartXScale(domain: domain)
    .chartYScale(optionalDomain: yDomain)
    .chartXSelection(value: $selectedDate)
    .scrollingIfNeeded(points.count > 8, visibleDomainLength: 7 * 86_400, scrollPosition: $scrollPosition)
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityLabel))
    .accessibilityValue(accessibilityValue)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      legend
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
    .onAppear(perform: resetScrollPosition)
    .onChange(of: points.first?.date) { _, _ in
      resetScrollPosition()
    }
    .onChange(of: points.count) { _, _ in
      resetScrollPosition()
    }
  }

  private var domain: ClosedRange<Date> {
    guard let start = points.first?.date, let end = points.last?.date else {
      return Date.now...Date.now.addingTimeInterval(86_400)
    }
    return start.addingTimeInterval(-domainPadding)...end.addingTimeInterval(domainPadding)
  }

  private func resetScrollPosition() {
    if let firstDate = points.first?.date {
      scrollPosition = firstDate
    }
  }
}

private extension View {
  @ViewBuilder
  func scrollingIfNeeded(
    _ shouldScroll: Bool,
    visibleDomainLength: TimeInterval,
    scrollPosition: Binding<Date>
  ) -> some View {
    if shouldScroll {
      self
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartScrollPosition(x: scrollPosition)
    } else {
      self
    }
  }

  @ViewBuilder
  func chartYScale(optionalDomain domain: ClosedRange<Double>?) -> some View {
    if let domain {
      chartYScale(domain: domain)
    } else {
      self
    }
  }
}
