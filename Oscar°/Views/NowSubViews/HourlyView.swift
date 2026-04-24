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
  @State private var showDetailView = false
  @State private var detailPresentationCount = 0

  private var items: [HourlyTimelineItem] {
    HourlyForecastBuilder.makeItems(
      forecast: weather.forecast,
      isLoading: weather.isLoading
    )
  }

  private var hasHourlyDetailData: Bool {
    HourlyForecastBuilder.hasHourlyDetailData(
      forecast: weather.forecast,
      isLoading: weather.isLoading
    )
  }

  private var shouldShowPlaceholders: Bool {
    weather.isLoading && items.isEmpty
  }

  var body: some View {
    let shouldReduceMotion = reduceMotion

    Button(action: presentDetails) {
      VStack(alignment: .leading) {
        Text("Stündlich")
          .font(.title3)
          .bold()
          .foregroundStyle(.primary)
          .padding(.leading)

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
          .font(.body)
          .padding(.leading)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .frame(maxWidth: .infinity)
      }
      .opacity(weather.isLoading || weather.forecast.hourly == nil ? 0.3 : 1.0)
      .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
    }
    .buttonStyle(.plain)
    .disabled(!hasHourlyDetailData)
    .accessibilityLabel(Text("Stündliche Details"))
    .accessibilityHint(Text("Öffnet die stündliche Wettervorhersage"))
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(shouldReduceMotion || phase.isIdentity ? 1 : 0.99)
        .blur(radius: shouldReduceMotion || phase.isIdentity ? 0 : 0.5)
    }
    .sensoryFeedback(.impact, trigger: detailPresentationCount)
    .sheet(isPresented: $showDetailView) {
      HourlyDetailView()
    }
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
    showDetailView = true
  }
}

#Preview {
  HourlyView()
    .frame(height: 200)
    .environment(Weather.mock)
}
