//
//  ForecastSettingsView.swift
//  Oscar°
//

import SwiftUI

struct ForecastSettingsView: View {
  private let settingsService = SettingService.shared

  var body: some View {
    NavigationStack {
      List {
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
          Toggle(isOn: Binding(
            get: { settingsService.dailyForecastDaytimeTemperaturesEnabled },
            set: { settingsService.dailyForecastDaytimeTemperaturesEnabled = $0 }
          )) {
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
            Picker(String(localized: "Zeitraum"), selection: Binding(
              get: { settingsService.dailyForecastDaytimeTemperatureRangeMode },
              set: { settingsService.dailyForecastDaytimeTemperatureRangeMode = $0 }
            )) {
              ForEach(ForecastDaytimeTemperatureRangeMode.allCases) { mode in
                Text(mode.label).tag(mode)
              }
            }

            if settingsService.dailyForecastDaytimeTemperatureRangeMode == .customHours {
              Picker(String(localized: "Start"), selection: Binding(
                get: { settingsService.dailyForecastDaytimeCustomStartHour },
                set: { settingsService.updateDailyForecastDaytimeCustomStartHour($0) }
              )) {
                ForEach(0...settingsService.dailyForecastDaytimeCustomEndHour, id: \.self) { hour in
                  Text(hourLabel(hour)).tag(hour)
                }
              }

              Picker(String(localized: "Ende"), selection: Binding(
                get: { settingsService.dailyForecastDaytimeCustomEndHour },
                set: { settingsService.updateDailyForecastDaytimeCustomEndHour($0) }
              )) {
                ForEach(settingsService.dailyForecastDaytimeCustomStartHour...23, id: \.self) { hour in
                  Text(hourLabel(hour)).tag(hour)
                }
              }
            }
          }
        }
      }
    }
    .navigationBarTitle("Vorhersage", displayMode: .inline)
  }

  private func hourLabel(_ hour: Int) -> String {
    let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    return SettingService.formattedTime(date, showsMinutes: false)
  }
}

struct ForecastSettingsLabel: View {
  var body: some View {
    HStack {
      Image(systemName: "calendar")
        .font(.body.weight(.semibold))
        .frame(width: 30, height: 30)
        .foregroundStyle(.white)
        .background(Color.teal)
        .clipShape(.rect(cornerRadius: 5))
      Text("Vorhersage")
    }
  }
}

#Preview {
  ForecastSettingsView()
}
