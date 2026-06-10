//
//  UnitSettings.swift
//  Oscar°
//
//  Created by Philipp Bolte on 06.07.24.
//

import SwiftUI

struct UnitSettings: View {
    private let settingsService = SettingService.shared

    var body: some View {
        NavigationView {
            List {
                Picker(String(localized: "Temperatur"), selection: Binding(
                    get: { settingsService.settings?.temperatureUnit ?? "celsius" },
                    set: { settingsService.updateTemperatureUnit($0) }
                )) {
                    Text("°C").tag("celsius")
                    Text("°F").tag("fahrenheit")
                }
                
                Picker(String(localized: "Windgeschwindigkeit"), selection: Binding(
                    get: { settingsService.settings?.windSpeedUnit ?? "kmh" },
                    set: { settingsService.updateWindSpeedUnit($0) }
                )) {
                    Text("km/h").tag("kmh")
                    Text("m/s").tag("ms")
                    Text("mph").tag("mph")
                    Text("kn").tag("kn")
                    Text("Bft").tag("bft")
                }
                
                Picker(String(localized: "Niederschlag"), selection: Binding(
                    get: { settingsService.settings?.precipitationUnit ?? "mm" },
                    set: { settingsService.updatePrecipitationUnit($0) }
                )) {
                    Text("mm").tag("mm")
                    Text("inch").tag("inch")
                }

                Picker(String(localized: "Zeitformat"), selection: Binding(
                    get: { settingsService.timeFormatPreference },
                    set: { preference in
                        settingsService.timeFormatPreference = preference
                        Task {
                            await NotificationSettingsManager.shared.syncTimeFormatPreferenceUpdate()
                        }
                    }
                )) {
                    ForEach(TimeFormatPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
            }
        }
        .navigationBarTitle("Einheiten", displayMode: .inline)
    }
}

struct UnitSettingsLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text("°C")
                .fontWeight(.medium)
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.orange)
                .cornerRadius(5)
            Text("Einheiten")
        }
    }
}

#Preview {
    UnitSettings()
}
