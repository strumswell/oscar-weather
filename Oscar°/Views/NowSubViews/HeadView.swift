//
//  HeadView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.

import CoreLocation
import SwiftUI

struct HeadView: View {
  @Environment(Weather.self) private var weather: Weather
  @Environment(Location.self) private var location: Location
  @Environment(NowPresentationCoordinator.self) private var presentation
  @ScaledMetric(relativeTo: .largeTitle) private var temperatureFontSize: CGFloat = 120
  @ScaledMetric(relativeTo: .title2) private var cityNameFontSize: CGFloat = 22
  private let settingsService = SettingService.shared
  private let cityService = CityService.shared

  private var windSpeedUnit: WindSpeedUnit {
    WindSpeedUnit(settingValue: settingsService.windSpeedUnit)
  }

  private var currentWindSpeed: Double? {
    let speed = weather.forecast.current?.windspeed
    guard windSpeedUnit.usesBeaufortDisplay else { return speed }
    return BeaufortScale.value(forKilometersPerHour: speed)
  }

  /// "🏠 Zuhause" above the place name: the selected city's personalization,
  /// or the current location's (UserDefaults-backed) when GPS is active.
  private var personalization: String? {
    let emoji: String?
    let label: String?
    if let city = cityService.cities.first(where: { $0.selected }) {
      emoji = city.emoji
      label = city.customLabel
    } else {
      emoji = cityService.currentLocationEmoji
      label = cityService.currentLocationCustomLabel
    }
    let text = [emoji, label]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return text.isEmpty ? nil : text
  }

  private var locationHeader: some View {
    VStack(spacing: 4) {
      if let personalization {
        // An "eyebrow" over the place name: small caps, letterspaced,
        // deliberately quiet next to the city name.
        Text(personalization)
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1.2)
          .foregroundStyle(Color(UIColor.label).opacity(0.6))
          .lineLimit(1)
      }
      Text(location.name)
        .font(.system(size: cityNameFontSize, weight: .bold))
        .lineSpacing(10)
        .foregroundStyle(Color(UIColor.label))
    }
  }

  var body: some View {
    HStack {
      Spacer()
      locationHeader
      Spacer()
    }
    .shadow(radius: 5)
    .onTapGesture {
      UIApplication.shared.playHapticFeedback()
      presentation.selectedTab = .search
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(
      Text("Ort ändern, aktuell \([personalization, location.name].compactMap { $0 }.joined(separator: ", "))")
    )
    .accessibilityAction {
      UIApplication.shared.playHapticFeedback()
      presentation.selectedTab = .search
    }
    .padding(.bottom, 10)
    .padding(.top)

    VStack {
      VStack {
        Spacer()
        Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
          .foregroundStyle(Color(UIColor.label))
          .font(.system(size: temperatureFontSize))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .shadow(radius: 15)
          .contentTransition(.numericText())
          .animation(.default, value: weather.forecast.current?.temperature)
      }
      .padding(.bottom, 155)

      HStack {
        Spacer()
        Image(systemName: "cloud")
          .frame(width: 30, height: 30)
          .foregroundStyle(Color(UIColor.label))
        Text("\(weather.forecast.current?.cloudcover ?? 0, specifier: "%.0f") %")
          .foregroundStyle(Color(UIColor.label))
        Image(systemName: "wind")
          .frame(width: 30, height: 30)
          .foregroundStyle(Color(UIColor.label))
        Text(WindSpeedFormatter.string(currentWindSpeed, unit: windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h"))
        .foregroundStyle(Color(UIColor.label))
        Image(systemName: "location")
          .frame(width: 30, height: 30)
          .foregroundStyle(Color(UIColor.label))
        Text(weather.forecast.current?.getWindDirection() ?? "")
        Spacer()
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Bewölkung \(Int((weather.forecast.current?.cloudcover ?? 0).rounded())) Prozent, Wind \(WindSpeedFormatter.string(currentWindSpeed, unit: windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h")), Richtung \(weather.forecast.current?.getWindDirection() ?? "unbekannt")"
      )
      .padding(.bottom)

      if hasWeatherAlerts() {
        AlertView()
          .padding(.bottom, 20)
      }
    }
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(phase.isIdentity ? 1 : 0.99)
        .blur(radius: phase.isIdentity ? 0 : 0.5)
    }
  }

}

extension HeadView {
  func hasWeatherAlerts() -> Bool {
    switch weather.alerts {
    case .brightsky(let brightskyAlerts):
      return (brightskyAlerts.alerts?.count ?? 0) > 0
    case .canadian(let canadianAlerts):
      return canadianAlerts.contains { $0.alert?.alerts?.isEmpty == false }
    case .oscar(let oscarAlerts):
      return !oscarAlerts.alerts.isEmpty
    }
  }
}
