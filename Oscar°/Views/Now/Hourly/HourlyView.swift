//
//  HourlyView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct HourlyView: View {
  @Environment(Weather.self) private var weather: Weather
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(NowPresentationCoordinator.self) private var presentation
  @State private var leadingItemID: String?

  private var items: [HourlyTimelineItem] {
    HourlyForecastBuilder.makeItems(
      forecast: weather.forecast,
      precipSeries: weather.precipSeries,
      isLoading: weather.isLoading
    )
  }

  private var hasHourlyDetailData: Bool {
    HourlyForecastBuilder.hasHourlyDetailData(forecast: weather.forecast)
  }

  var body: some View {
    let shouldReduceMotion = reduceMotion
    let items = self.items
    let shouldShowPlaceholders = weather.isLoading && items.isEmpty
    let timeZone = weather.forecast.locationTimeZone
    let now = Date(timeIntervalSince1970: weather.forecast.current?.time ?? 0)
    let firstID = items.first?.id
    let leadingItem = items.first { $0.id == leadingItemID }
    let dayLabel = leadingItem.map {
      HourlyFormatting.dayLabel(timestamp: $0.timestamp, timeZone: timeZone, now: now)
    }
    let showDayBadge = leadingItemID != nil && leadingItemID != firstID && dayLabel != nil

    VStack(alignment: .leading) {
      header(dayLabel: showDayBadge ? dayLabel : nil)

      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          if shouldShowPlaceholders {
            ForEach(0..<10, id: \.self) { _ in
              HourlyPlaceholderCard()
                .scrollTransition { content, phase in
                  content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.9)
                }
                .padding(.vertical, 20)
            }
          } else {
            ForEach(items) { item in
              timelineItemView(item)
                .scrollTransition { content, phase in
                  content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.9)
                }
                .padding(.vertical, 20)
                .onTapGesture {
                  presentDetails(at: Date(timeIntervalSince1970: item.timestamp))
                }
            }
          }
        }
        .scrollTargetLayout()
        .font(.system(size: 18))
        .padding(.leading)
      }
      .scrollIndicators(.hidden)
      // .never lets a flick travel several cards; the default limit stops
      // momentum after one page, which reads as a stiff scroll.
      .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
      .scrollPosition(id: $leadingItemID)
      .contentMargins(.trailing, 16, for: .scrollContent)
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
      .onTapGesture(perform: presentDetails)
      .disabled(!hasHourlyDetailData)
      .accessibilityAction(named: Text("Stündliche Details"), presentDetails)
    }
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.99)
    }
    .accessibilityIdentifier("now.hourly")
  }

  private func header(dayLabel: String?) -> some View {
    NowSectionHeader(showMore: hasHourlyDetailData ? { presentDetails(at: nil) } : nil) {
      HStack(spacing: 6) {
        Text("Stündlich")
          .contentShape(.rect)
          .onTapGesture { scrollToStart() }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint(Text("Zurück zum Anfang der stündlichen Vorhersage"))

        if let dayLabel {
          Text(verbatim: "· \(dayLabel)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .transition(.opacity)
        }
      }
      .animation(.snappy, value: dayLabel)
    }
  }

  /// Single-root container keeps the lazy row unary, so the stack can template
  /// row identity without evaluating every card.
  private func timelineItemView(_ item: HourlyTimelineItem) -> some View {
    VStack(spacing: 0) {
      switch item {
      case .forecast(let forecast):
        HourlyForecastCard(item: forecast)
      case .sunEvent(let sunEvent):
        HourlySunEventCard(item: sunEvent)
      }
    }
  }

  private func presentDetails() {
    presentDetails(at: nil)
  }

  private func presentDetails(at target: Date?) {
    guard hasHourlyDetailData else {
      return
    }

    presentation.present(.hourly(target))
  }

  private func scrollToStart() {
    // Only act when actually scrolled away from the start (nil = untouched = already there).
    guard let firstID = items.first?.id, let current = leadingItemID, current != firstID else {
      return
    }

    withAnimation(.snappy) { leadingItemID = firstID }
  }
}

#Preview {
  HourlyView()
    .frame(height: 200)
    .environment(Weather.mock)
    .environment(NowPresentationCoordinator())
}
