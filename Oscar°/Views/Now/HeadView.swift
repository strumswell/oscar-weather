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

  // Classic Oscar composition: the temperature floats alone in the sky and
  // the metrics anchor the bottom of the gap just above the first card — but
  // the two sky gaps are flexible, not fixed. NowView stretches the head so
  // the hourly strip below it ends right at the tab bar; the gaps soak up
  // whatever the screen size and the optional content (alert, radar card,
  // eyebrow) leave over, and compress down to these floors before the page
  // starts to overflow and scroll.
  private static let temperatureGapMinHeight: CGFloat = 70
  private static let metricsGapMinHeight: CGFloat = 110

  private var windSpeedUnit: WindSpeedUnit {
    WindSpeedUnit(settingValue: settingsService.windSpeedUnit)
  }

  private var currentWindSpeed: Double? {
    let speed = weather.forecast.current?.windspeed
    guard windSpeedUnit.usesBeaufortDisplay else { return speed }
    return BeaufortScale.value(forKilometersPerHour: speed)
  }

  /// The active place's personalization: the selected city's, or the current
  /// location's (UserDefaults-backed) when GPS is active.
  private var activePersonalization: PlacePersonalization {
    cityService.cities.first(where: { $0.selected })?.personalization
      ?? cityService.currentLocationPersonalization
  }

  /// "🏠 Zuhause" above the place name: an emoji mark, then the custom label —
  /// never the generic base name, the city name below already covers that.
  /// The GPS entry's standard location glyph sits inline with the name instead.
  private var eyebrow: Text? {
    let personalization = activePersonalization
    var parts: [Text] = []
    if let emoji = personalization.mark.emoji {
      parts.append(Text(emoji))
    }
    if let label = personalization.customLabel {
      parts.append(Text(label))
    }
    guard let first = parts.first else { return nil }
    return parts.dropFirst().reduce(first) { $0 + Text(verbatim: " ") + $1 }
  }

  /// The GPS entry keeps its standard glyph directly before the resolved
  /// place name; an emoji choice moves to the eyebrow, "no icon" leaves the
  /// name bare.
  private var showsLocationGlyph: Bool {
    cityService.cities.first(where: { $0.selected }) == nil
      && gpsAuthorized
      && cityService.currentLocationPersonalization.mark == .locationGlyph
  }


  /// Spoken form of the eyebrow — the location glyph is decoration, so only
  /// emoji and label count here.
  private var eyebrowDescription: String? {
    let personalization = activePersonalization
    let text = [personalization.mark.emoji, personalization.customLabel]
      .compactMap { $0 }
      .joined(separator: " ")
    return text.isEmpty ? nil : text
  }

  private var gpsAuthorized: Bool {
    let status = LocationService.shared.authStatus
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private static let trendTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
  }()

  /// Arrow + minute for the cloud metric's annotation: the screenshot mock
  /// (`-mockCloudTrend`) wins, otherwise the satellite series' detected
  /// transition — nil (the usual case) renders nothing.
  private var cloudTrendAnnotation: (arrow: String, time: String)? {
    if let mock = MockCloudTrend.current { return (mock.arrow, mock.time) }
    guard let trend = weather.cloudSeries?.trend() else { return nil }
    return (trend.direction == .clearing ? "arrow.down.right" : "arrow.up.right",
            Self.trendTimeFormatter.string(from: trend.at))
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
    let personalization = city.personalization
    let title = [personalization.mark.emoji, personalization.title]
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
      if let eyebrow {
        // An "eyebrow" over the place name: small caps, letterspaced,
        // deliberately quiet next to the city name.
        eyebrow
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1.2)
          .foregroundStyle(Color(UIColor.label).opacity(0.6))
          .lineLimit(1)
          // Mutes the emoji too — foregroundStyle can't touch its colors, and
          // at full saturation it outweighs the city name above it.
          .opacity(0.8)
      }
      HStack(spacing: 6) {
        if showsLocationGlyph {
          // Concatenated Text put the small glyph on the name's baseline,
          // hanging low — the stack centers it on the optical middle. Muted
          // to the eyebrow's level so the name keeps the weight.
          Image(systemName: "location.fill")
            .font(.system(size: cityNameFontSize * 0.55, weight: .bold))
            .foregroundStyle(Color(UIColor.label).opacity(0.75))
        }
        Text(location.name)
          .font(.system(size: cityNameFontSize, weight: .bold))
          .lineSpacing(10)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color(UIColor.label))
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        locationHeader
        Spacer()
      }
      .shadow(radius: 5)
      .contentShape(Rectangle())
      .onTapGesture {
        UIApplication.shared.playHapticFeedback()
        presentation.selectedTab = .places
      }
      // Long-press shortcut for switching places without leaving the
      // forecast — Tab accepts no gestures or menus, so it lives here.
      .contextMenu {
        locationSwitchPicker
        Divider()
        Button {
          UIApplication.shared.playHapticFeedback()
          presentation.selectedTab = .places
        } label: {
          Label("Orte verwalten", systemImage: "list.bullet")
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(
        Text("Ort ändern, aktuell \([eyebrowDescription, location.name].compactMap { $0 }.joined(separator: ", "))")
      )
      .accessibilityAction {
        UIApplication.shared.playHapticFeedback()
        presentation.selectedTab = .places
      }
      .padding(.bottom, 10)
      .padding(.top)

      VStack(spacing: 0) {
        Spacer(minLength: Self.temperatureGapMinHeight)

        Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
          .foregroundStyle(Color(UIColor.label))
          .font(.system(size: temperatureFontSize))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .shadow(radius: 15)
          .contentTransition(.numericText())
          .animation(.default, value: weather.forecast.current?.temperature)

        Spacer(minLength: Self.metricsGapMinHeight)

        HStack(spacing: 6) {
          Spacer()
          Image(systemName: "cloud")
          Text("\(MockCloudTrend.current?.cover ?? weather.forecast.current?.cloudcover ?? 0, specifier: "%.0f") %")
          if let annotation = cloudTrendAnnotation {
            // The satellite nowcast's sky transition rides inline after the
            // cloud value — smaller type, optically centered on the row.
            HStack(spacing: 2) {
              Image(systemName: annotation.arrow)
                .font(.system(size: 9, weight: .bold))
              Text(annotation.time)
                .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Color(UIColor.label).opacity(0.55))
          }
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

        if hasWeatherAlerts() || weather.primaryMeteorEvent != nil {
          VStack(spacing: 8) {
            if hasWeatherAlerts() {
              AlertView()
            }
            if let event = weather.primaryMeteorEvent {
              MeteorAlertView(event: event)
            }
          }
          .padding(.top, 14)
        }
      }
      .padding(.bottom, 40)
      .scrollTransition { content, phase in
        content
          .opacity(phase.isIdentity ? 1 : 0.8)
          .scaleEffect(phase.isIdentity ? 1 : 0.99)
      }
    }
  }

}

/// UI MOCK of the satellite cloud-trend hint (metrics-row variant): only active
/// with `-mockCloudTrend clearing|clouding`.
private enum MockCloudTrend: String {
  case clearing
  case clouding

  static var current: MockCloudTrend? {
    UserDefaults.standard.string(forKey: "mockCloudTrend").flatMap(MockCloudTrend.init)
  }

  var cover: Double { self == .clearing ? 92 : 5 }
  var arrow: String { self == .clearing ? "arrow.down.right" : "arrow.up.right" }
  var time: String { self == .clearing ? "22:40" : "23:15" }
}

extension HeadView {
  func hasWeatherAlerts() -> Bool {
    switch weather.alerts {
    case .canadian(let canadianAlerts):
      return canadianAlerts.contains { $0.alert?.alerts?.isEmpty == false }
    case .oscar(let oscarAlerts):
      return !oscarAlerts.alerts.isEmpty
    }
  }
}
