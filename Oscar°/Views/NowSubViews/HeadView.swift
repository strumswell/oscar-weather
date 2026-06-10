//
//  HeadView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.

import CoreLocation
import SwiftUI

struct HeadView: View {
  let locationTransition: Namespace.ID
  @Environment(Weather.self) private var weather: Weather
  @Environment(Location.self) private var location: Location
  @Environment(NowPresentationCoordinator.self) private var presentation
  @ScaledMetric(relativeTo: .largeTitle) private var temperatureFontSize: CGFloat = 120
  private let settingsService = SettingService.shared

  private var windSpeedUnit: WindSpeedUnit {
    WindSpeedUnit(settingValue: settingsService.settings?.windSpeedUnit)
  }

  private var currentWindSpeed: Double? {
    let speed = weather.forecast.current?.windspeed
    guard windSpeedUnit.usesBeaufortDisplay else { return speed }
    return BeaufortScale.value(forKilometersPerHour: speed)
  }

  var body: some View {
    HStack {
      Spacer()
        if #available(iOS 18.0, *) {
            HStack {
                Image(systemName: "magnifyingglass")
                  .foregroundColor(Color(UIColor.label))
                Text(location.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineSpacing(10)
                    .foregroundColor(Color(UIColor.label))
            }
            .matchedTransitionSource(id: NowSheet.locationTransitionID, in: locationTransition)
        } else {
            Image(systemName: "magnifyingglass")
              .foregroundColor(Color(UIColor.label))
            Text(location.name)
                .font(.title2)
                .fontWeight(.bold)
                .lineSpacing(10)
                .foregroundColor(Color(UIColor.label))
        }
      Spacer()
    }
    .opacity(weather.isLoading && !weather.hasContent ? 0.3 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
    .shadow(radius: 5)
    .onTapGesture {
      UIApplication.shared.playHapticFeedback()
      presentation.present(.location)
    }
    .padding(.bottom, 35)
    .padding(.leading, -20)
    .padding(.top)

    VStack {
      VStack {
        Spacer()
        Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
          .foregroundColor(Color(UIColor.label))
          .font(.system(size: temperatureFontSize))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .shadow(radius: 15)
          .contentTransition(.numericText())
      }
      .padding(.bottom, 170)

      HStack {
        Spacer()
        Image(systemName: "cloud")
          .frame(width: 30, height: 30)
          .foregroundColor(Color(UIColor.label))
        Text("\(weather.forecast.current?.cloudcover ?? 0, specifier: "%.0f") %")
          .foregroundColor(Color(UIColor.label))
          .contentTransition(.numericText())
        Image(systemName: "wind")
          .frame(width: 30, height: 30)
          .foregroundColor(Color(UIColor.label))
        Text(WindSpeedFormatter.string(currentWindSpeed, unit: windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h"))
        .foregroundColor(Color(UIColor.label))
        .contentTransition(.numericText())
        Image(systemName: "location")
          .frame(width: 30, height: 30)
          .foregroundColor(Color(UIColor.label))
        Text(weather.forecast.current?.getWindDirection() ?? "")
        Spacer()
      }
      .padding(.bottom)

      if hasWeatherAlerts() {
        AlertView()
          .padding(.bottom, 20)
      }
    }
    .opacity(weather.isLoading && !weather.hasContent ? 0.3 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
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
    }
  }
}
