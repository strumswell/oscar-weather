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
  @State private var isLocationSheetPresented = false

  var body: some View {
    HStack {
      Spacer()
      Image(systemName: "magnifyingglass")
        .foregroundColor(Color(UIColor.label))
      Text(location.name)
        .font(.title2)
        .fontWeight(.bold)
        .lineSpacing(10)
        .foregroundColor(Color(UIColor.label))
      Spacer()
    }
    .opacity(weather.isLoading ? 0.3 : 1.0)
    .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
    .shadow(radius: 5)
    .onTapGesture {
      UIApplication.shared.playHapticFeedback()
      isLocationSheetPresented.toggle()
    }
    .sheet(isPresented: $isLocationSheetPresented) {
      SearchCityView()
    }
    .padding(.bottom, 35)
    .padding(.leading, -20)
    .padding(.top)

    VStack {
      VStack {
        Spacer()
        Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
          .foregroundColor(Color(UIColor.label))
          .font(.system(size: 120))
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
        Text(
          "\(weather.forecast.current?.windspeed ?? 0, specifier: "%.1f") \(weather.forecast.hourly_units?.windspeed_10m ?? "km/h")"
        )
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
    .opacity(weather.isLoading ? 0.3 : 1.0)
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
