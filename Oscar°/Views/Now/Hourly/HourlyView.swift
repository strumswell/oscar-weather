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
  @State private var detailPresentationCount = 0
  @State private var leadingItemID: String?
  @State private var observingDate = Date.now

  private var nextMeteorUpdate: Date? {
    guard let window = weather.primaryMeteorEvent?.bestWindow else { return nil }
    return [window.start, window.end].filter { $0 > observingDate }.min()
  }

  private var items: [HourlyDisplayItem] {
    var items = HourlyForecastBuilder.makeItems(
      forecast: weather.forecast,
      precipSeries: weather.precipSeries,
      isLoading: weather.isLoading
    ).map(HourlyDisplayItem.weather)

    if let response = weather.meteorShowerResponse,
       let notice = MeteorShowerForecast.notice(in: response, now: observingDate),
       let first = items.first, let last = items.last,
       notice.date.timeIntervalSince1970 >= first.timestamp,
       notice.date.timeIntervalSince1970 <= last.timestamp {
      let index = items.firstIndex { $0.timestamp > notice.date.timeIntervalSince1970 } ?? items.endIndex
      items.insert(.meteor(notice.event, notice.date), at: index)
    }
    return items
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
            .foregroundStyle(.primary.opacity(0.8))
            .contentTransition(.numericText())
            .transition(.opacity)
        }
      }
      .padding(.horizontal)
      .animation(.snappy, value: dayLabel)
      .animation(.snappy, value: showDayBadge)

      Group {
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
              }
            }
          }
          .scrollTargetLayout()
          .font(.system(size: 18))
          .padding(.leading)
        }
        .accessibilityIdentifier("now.hourly.strip")
        .scrollIndicators(.hidden)
        // .never lets a flick travel several cards; the default limit stops
        // momentum after one page, which reads as a stiff scroll.
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollPosition(id: $leadingItemID)
        .contentMargins(.trailing, 16, for: .scrollContent)
        .frame(maxWidth: .infinity)
      }
      .accessibilityAction(named: Text("Stündliche Details"), presentDetails)
    }
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.99)
    }
    .sensoryFeedback(.impact, trigger: detailPresentationCount)
    .task(id: nextMeteorUpdate) {
      // Expire the notice even when the forecast stays open without a refresh.
      observingDate = .now
      guard let nextMeteorUpdate else { return }
      do {
        try await Task.sleep(for: .seconds(max(0, nextMeteorUpdate.timeIntervalSinceNow)))
        observingDate = .now
      } catch {
        // Leaving this view or receiving newer data cancels the old deadline.
      }
    }
  }

  @ViewBuilder
  private func timelineItemView(_ item: HourlyDisplayItem) -> some View {
    switch item {
    case .weather(let item):
      Button {
        presentDetails(at: Date(timeIntervalSince1970: item.timestamp))
      } label: {
        switch item {
        case .forecast(let forecast):
          HourlyForecastCard(item: forecast)
        case .sunEvent(let sunEvent):
          HourlySunEventCard(item: sunEvent)
        }
      }
      .buttonStyle(.plain)
      .disabled(!hasHourlyDetailData)
      .accessibilityIdentifier("now.hourly.forecast.\(item.id)")
    case .meteor(let event, let date):
      MeteorShowerNotice(
        event: event,
        phase: MeteorShowerPhase.of(event, night: weather.meteorShowerResponse?.night, now: observingDate),
        date: date,
        timeZone: weather.forecast.locationTimeZone
      )
    }
  }

  private func presentDetails() {
    presentDetails(at: nil)
  }

  private func presentDetails(at target: Date?) {
    guard hasHourlyDetailData else {
      return
    }

    detailPresentationCount += 1
    presentation.present(.hourly(target))
  }

  private func scrollToStart() {
    // Only act when actually scrolled away from the start (nil = untouched = already there).
    guard let firstID = items.first?.id, let current = leadingItemID, current != firstID else {
      return
    }

    Haptics.impact()
    withAnimation(.snappy) { leadingItemID = firstID }
  }
}

/// Presentation-only additions keep the shared iPhone/Watch weather timeline
/// unchanged. The observing notice uses the same ordering and scroll IDs.
private enum HourlyDisplayItem: Identifiable {
  case weather(HourlyTimelineItem)
  case meteor(MeteorShowerEvent, Date)

  var id: String {
    switch self {
    case .weather(let item): item.id
    case .meteor(let event, _): "meteor-\(event.id)"
    }
  }

  var timestamp: Double {
    switch self {
    case .weather(let item): item.timestamp
    case .meteor(_, let date): date.timeIntervalSince1970
    }
  }
}

#Preview {
  HourlyView()
    .frame(height: 200)
    .environment(Weather.mock)
    .environment(NowPresentationCoordinator())
}
