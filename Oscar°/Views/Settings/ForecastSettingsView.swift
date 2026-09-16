//
//  ForecastSettingsView.swift
//  Oscar°
//

import SwiftUI

struct ForecastSettingsView: View {
  @Bindable private var settingsService = SettingService.shared

  var body: some View {
    Form {
        Section {
          NavigationLink {
            ForecastModelSettingsView()
          } label: {
            HStack {
              Text("Wettermodell")
              Spacer()
              Text(settingsService.forecastModelPreference.name)
                .foregroundStyle(.secondary)
            }
          }
        } footer: {
          Text("Standardmäßig wählt Oscar automatisch das beste Wettermodell. Fortgeschrittene Nutzer können ein bestimmtes Modell erzwingen.")
        }

        Section {
          Toggle(isOn: $settingsService.dailyForecastDaytimeTemperaturesEnabled) {
            Text("Tageswerte begrenzen")
          }
        } footer: {
          Text("Begrenzt Hoch/Tief auf einen Zeitraum, z. B. für relevantere Tiefstwerte nach Sonnenaufgang.")
        }

        if settingsService.dailyForecastDaytimeTemperaturesEnabled {
          Section {
            VStack(spacing: 10) {
              ForEach(ForecastDaytimeTemperatureDisplayMode.allCases) { mode in
                ForecastDisplayModeOption(
                  mode: mode,
                  isSelected: settingsService.dailyForecastDaytimeTemperatureDisplayMode == mode
                ) {
                  settingsService.dailyForecastDaytimeTemperatureDisplayMode = mode
                }
              }
            }
            .padding(.vertical, 4)
          } footer: {
            Text("Wähle, ob die Tageswerte ersetzt oder im 24-Stunden-Bereich markiert werden.")
          }

          Section {
            Picker("Zeitraum", selection: $settingsService.dailyForecastDaytimeTemperatureRangeMode) {
              ForEach(ForecastDaytimeTemperatureRangeMode.allCases) { mode in
                Text(mode.label).tag(mode)
              }
            }

            if settingsService.dailyForecastDaytimeTemperatureRangeMode == .customHours {
              Picker("Start", selection: $settingsService.dailyForecastDaytimeCustomStartHour) {
                ForEach(0...settingsService.dailyForecastDaytimeCustomEndHour, id: \.self) { hour in
                  Text(hourLabel(hour)).tag(hour)
                }
              }

              Picker("Ende", selection: $settingsService.dailyForecastDaytimeCustomEndHour) {
                ForEach(settingsService.dailyForecastDaytimeCustomStartHour...23, id: \.self) { hour in
                  Text(hourLabel(hour)).tag(hour)
                }
              }
            }
          }
        }
    }
    .navigationTitle("Vorhersage")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func hourLabel(_ hour: Int) -> String {
    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    return SettingService.formattedTime(date, showsMinutes: false)
  }
}

#Preview {
  NavigationStack {
    ForecastSettingsView()
  }
}
