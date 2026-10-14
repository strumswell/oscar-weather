//
//  HeadView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 24.10.20.

import CoreLocation
import SwiftUI

struct HeadView: View {
  var compact = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(Weather.self) private var weather: Weather
  @Environment(Location.self) private var location: Location
  @Environment(NowPresentationCoordinator.self) private var presentation
  @ScaledMetric(relativeTo: .largeTitle) private var temperatureFontSize: CGFloat = 120
  @ScaledMetric(relativeTo: .title2) private var cityNameFontSize: CGFloat = 22
  private let settingsService = SettingService.shared
  private let cityService = CityService.shared

  private static let temperatureGapMinHeight: CGFloat = 70
  private static let metricsGapMinHeight: CGFloat = 110

  private var metricsDescription: String {
    settingsService.headMetrics.compactMap { metric in
      metric.value(in: weather).map { "\(String(localized: metric.title)) \($0)" }
    }
    .joined(separator: ", ")
  }

  private var activePersonalization: PlacePersonalization {
    cityService.cities.first(where: { $0.selected })?.personalization
      ?? cityService.currentLocationPersonalization
  }

  private var eyebrow: Text? {
    eyebrowDescription.map { Text(verbatim: $0) }
  }

  private var showsLocationGlyph: Bool {
    cityService.cities.first(where: { $0.selected }) == nil
      && gpsAuthorized
      && cityService.currentLocationPersonalization.mark == .locationGlyph
  }


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

  private var cloudTrendAnnotation: (arrow: String, time: String)? {
    guard let trend = weather.cloudSeries?.trend() else { return nil }
    return (trend.direction == .clearing ? "arrow.down.right" : "arrow.up.right",
            SettingService.formattedTime(trend.at, timeZone: weather.forecast.locationTimeZone))
  }

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
    cityService.toggleActiveCity(city: city)
  }

  private func switchToCurrentLocation() {
    guard cityService.getSelectedCity() != nil else { return }
    cityService.disableAllCities()
  }

  private var locationHeader: some View {
    VStack(spacing: 4) {
      if let eyebrow {
        eyebrow
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .tracking(1.2)
          .foregroundStyle(Color(uiColor: .label).opacity(0.6))
          .lineLimit(1)
          .opacity(0.8)
      }
      HStack(spacing: 6) {
        if showsLocationGlyph {
          Image(systemName: "location.fill")
            .font(.system(size: cityNameFontSize * 0.55, weight: .bold))
            .foregroundStyle(Color(uiColor: .label).opacity(0.75))
        }
        Text(location.name)
          .font(.system(size: cityNameFontSize, weight: .bold))
          .lineSpacing(10)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color(uiColor: .label))
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
        presentation.selectedTab = .places
      }
      .contextMenu {
        locationSwitchPicker
        Divider()
        Button {
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
        presentation.selectedTab = .places
      }
      .padding(.bottom, 10)
      .padding(.top)

      VStack(spacing: 0) {
        Spacer(minLength: compact ? 8 : Self.temperatureGapMinHeight)

        Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
          .foregroundStyle(Color(uiColor: .label))
          .font(.system(size: temperatureFontSize))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .shadow(radius: 15)
          .contentTransition(.numericText())
          .catPerch()
          .animation(.default, value: weather.forecast.current?.temperature)
          .accessibilityLabel(Text("Temperatur \(roundTemperatureString(temperature: weather.forecast.current?.temperature))"))

        Spacer(minLength: compact ? 16 : Self.metricsGapMinHeight)

        HStack(spacing: 18) {
          ForEach(settingsService.headMetrics) { metric in
            if let value = metric.value(in: weather) {
              let item = HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                Text(value)
                if metric == .cloudCover, let annotation = cloudTrendAnnotation {
                  HStack(spacing: 2) {
                    Image(systemName: annotation.arrow)
                      .font(.system(size: 9, weight: .bold))
                    Text(annotation.time)
                      .font(.caption2.weight(.medium))
                  }
                  .foregroundStyle(Color(uiColor: .label).opacity(0.55))
                }
              }
              .catShelf()
              if metric == .measured, let id = weather.headStation?.id {
                Button { presentation.present(.stations(id)) } label: { item }
                  .buttonStyle(.plain)
              } else {
                item
              }
            }
          }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color(uiColor: .label).opacity(0.85))
        .shadow(radius: 3)
        .frame(maxWidth: .infinity, minHeight: 20)
        .contentShape(.rect)
        .onLongPressGesture {
          Haptics.impact()
          presentation.present(.layout)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("now.metrics")
        .accessibilityLabel(Text(metricsDescription))
        .accessibilityActions {
          if settingsService.headMetrics.contains(.measured), let id = weather.headStation?.id {
            Button("Messstationen") { presentation.present(.stations(id)) }
          }
          Button("Kennzahlen anpassen") { presentation.present(.layout) }
        }

        if hasWeatherAlerts() {
          AlertView()
            .padding(.top, 14)
        }
      }
      .padding(.bottom, 40)
      .scrollTransition { [reduceMotion] content, phase in
        content
          .opacity(phase.isIdentity ? 1 : 0.8)
          .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.99)
      }
    }
  }

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
