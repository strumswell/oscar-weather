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

  private var gpsAuthorized: Bool {
    let status = LocationService.shared.authStatus
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  /// Exclusive selection over the saved places, tagged by objectID URI;
  /// `nil` is the GPS pseudo-entry. Transient menu content, so the manual
  /// binding can't go stale.
  private var locationSwitchPicker: some View {
    Picker("Ort", selection: Binding(
      get: { cityService.getSelectedCity()?.objectID.uriRepresentation() },
      set: { (uri: URL?) in
        if let uri, let city = cityService.cities.first(where: { $0.objectID.uriRepresentation() == uri }) {
          switchTo(city)
        } else {
          switchToCurrentLocation()
        }
      }
    )) {
      if gpsAuthorized {
        Label(cityService.currentLocationDisplayName, systemImage: "location")
          .tag(URL?.none)
      }
      ForEach(cityService.cities, id: \.objectID) { city in
        Text(menuTitle(for: city))
          .tag(Optional(city.objectID.uriRepresentation()))
      }
    }
    .pickerStyle(.inline)
  }

  private func menuTitle(for city: City) -> String {
    let title = [city.emoji, city.displayName]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return title.isEmpty ? String(localized: "Unbekannter Ort") : title
  }

  private func switchTo(_ city: City) {
    guard !city.selected else { return }
    UIApplication.shared.playHapticFeedback()
    cityService.toggleActiveCity(city: city)
  }

  private func switchToCurrentLocation() {
    guard cityService.getSelectedCity() != nil else { return }
    UIApplication.shared.playHapticFeedback()
    cityService.disableAllCities()
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
          // Mutes the emoji too — foregroundStyle can't touch its colors, and
          // at full saturation it outweighs the city name above it.
          .opacity(0.8)
      }
      Text(location.name)
        .font(.system(size: cityNameFontSize, weight: .bold))
        .lineSpacing(10)
        .multilineTextAlignment(.center)
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
    .contentShape(Rectangle())
    .onTapGesture {
      UIApplication.shared.playHapticFeedback()
      presentation.selectedTab = .search
    }
    // Long-press shortcut for switching places without leaving the forecast.
    // Lives here because the tab bar's search pill is system-owned — Tab
    // accepts no gestures or menus.
    .contextMenu {
      locationSwitchPicker
      Divider()
      Button {
        UIApplication.shared.playHapticFeedback()
        presentation.selectedTab = .search
      } label: {
        Label("Orte verwalten", systemImage: "list.bullet")
      }
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

    VStack(spacing: 0) {
      Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
        .foregroundStyle(Color(UIColor.label))
        .font(.system(size: temperatureFontSize))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .shadow(radius: 15)
        .contentTransition(.numericText())
        .animation(.default, value: weather.forecast.current?.temperature)
        .padding(.top, 70)

      HStack(spacing: 6) {
        Spacer()
        Image(systemName: "cloud")
        Text("\(weather.forecast.current?.cloudcover ?? 0, specifier: "%.0f") %")
        Image(systemName: "wind")
          .padding(.leading, 12)
        Text(WindSpeedFormatter.string(currentWindSpeed, unit: windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h"))
        Image(systemName: "location")
          .padding(.leading, 12)
        Text(weather.forecast.current?.getWindDirection() ?? "")
        Spacer()
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(Color(UIColor.label).opacity(0.85))
      .shadow(radius: 3)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Bewölkung \(Int((weather.forecast.current?.cloudcover ?? 0).rounded())) Prozent, Wind \(WindSpeedFormatter.string(currentWindSpeed, unit: windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h")), Richtung \(weather.forecast.current?.getWindDirection() ?? "unbekannt")"
      )
      .padding(.top, 150)

      if hasWeatherAlerts() {
        AlertView()
          .padding(.top, 14)
      }
    }
    // Classic Oscar composition: the temperature floats alone in the sky, and
    // the metrics anchor the bottom of the gap just above the first card.
    .padding(.bottom, 40)
    .scrollTransition { content, phase in
      content
        .opacity(phase.isIdentity ? 1 : 0.8)
        .scaleEffect(phase.isIdentity ? 1 : 0.99)
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
