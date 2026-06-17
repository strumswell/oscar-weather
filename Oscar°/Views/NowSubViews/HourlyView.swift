//
//  HourlyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct HourlyView: View {
  @Environment(Weather.self) private var weather: Weather
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(NowPresentationCoordinator.self) private var presentation
  @State private var detailPresentationCount = 0
  @State private var leadingItemID: String?

  private var items: [HourlyTimelineItem] {
    HourlyForecastBuilder.makeItems(
      forecast: weather.forecast,
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
    let timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? .current
    let now = Date(timeIntervalSince1970: weather.forecast.current?.time ?? 0)
    let firstID = items.first?.id
    let leadingItem = items.first { $0.id == leadingItemID }
    let dayLabel = leadingItem.map {
      HourlyFormatting.dayLabel(timestamp: $0.timestamp, timeZone: timeZone, now: now)
    }
    let showDayBadge = leadingItemID != nil && leadingItemID != firstID && dayLabel != nil

    VStack(alignment: .leading) {
      HStack {
        Text("Stündlich")
          .font(.title3)
          .bold()
          .foregroundStyle(.primary)
          .contentShape(.rect)
          .onTapGesture { scrollToStart() }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint(Text("Zurück zum Anfang der stündlichen Vorhersage"))

        Spacer()

        if showDayBadge, let dayLabel {
          Text(dayLabel)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .transition(.opacity)
        }
      }
      .padding(.horizontal)
      .animation(.snappy, value: dayLabel)
      .animation(.snappy, value: showDayBadge)

      Button(action: presentDetails) {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 12) {
            if shouldShowPlaceholders {
              ForEach(0..<10, id: \.self) { _ in
                HourlyPlaceholderCard()
                  .scrollTransition { content, phase in
                    content
                      .opacity(phase.isIdentity ? 1 : 0.5)
                      .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.9)
                      .blur(radius: shouldReduceMotion || phase.isIdentity ? 0 : 2)
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
                      .blur(radius: shouldReduceMotion || phase.isIdentity ? 0 : 2)
                  }
                  .padding(.vertical, 20)
              }
            }
          }
          .scrollTargetLayout()
          .font(.system(size: 18))
          .padding(.leading)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $leadingItemID)
        .contentMargins(.trailing, 16, for: .scrollContent)
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.plain)
      .disabled(!hasHourlyDetailData)
      .accessibilityLabel(Text("Stündliche Details"))
      .accessibilityHint(Text("Öffnet die stündliche Wettervorhersage"))
    }
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.99)
        .blur(radius: shouldReduceMotion || phase.isIdentity ? 0 : 0.5)
    }
    .sensoryFeedback(.impact, trigger: detailPresentationCount)
  }

  @ViewBuilder
  private func timelineItemView(_ item: HourlyTimelineItem) -> some View {
    switch item {
    case .forecast(let forecast):
      HourlyForecastCard(item: forecast)
    case .sunEvent(let sunEvent):
      HourlySunEventCard(item: sunEvent)
    }
  }

  private func presentDetails() {
    guard hasHourlyDetailData else {
      return
    }

    detailPresentationCount += 1
    presentation.present(.hourly)
  }

  private func scrollToStart() {
    // Only act when actually scrolled away from the start (nil = untouched = already there).
    guard let firstID = items.first?.id, let current = leadingItemID, current != firstID else {
      return
    }

    UIApplication.shared.playHapticFeedback()
    withAnimation(.snappy) { leadingItemID = firstID }
  }
}

#Preview {
  HourlyView()
    .frame(height: 200)
    .environment(Weather.mock)
    .environment(NowPresentationCoordinator())
}
