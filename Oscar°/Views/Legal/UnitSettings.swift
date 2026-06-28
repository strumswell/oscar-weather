//
//  UnitSettings.swift
//  Oscar°
//
//  Created by Philipp Bolte on 06.07.24.
//

import SwiftUI

struct UnitSettings: View {
    private let settingsService = SettingService.shared

    // The unit fields live on the Core Data `Settings` object as @NSManaged properties, so mutating
    // them fires no @Observable change — a Picker bound straight to the service kept showing the old
    // value until the view was recreated. Seeding local @State (fresh on every push) and writing
    // through in `.onChange` makes each Picker reflect the tap immediately, then persists + refetches.
    @State private var temperatureUnit = SettingService.shared.settings?.temperatureUnit ?? "celsius"
    @State private var windSpeedUnit = SettingService.shared.settings?.windSpeedUnit ?? "kmh"
    @State private var precipitationUnit = SettingService.shared.settings?.precipitationUnit ?? "mm"
    @State private var timeFormatPreference = SettingService.shared.timeFormatPreference

    var body: some View {
        NavigationStack {
            List {
                Picker(String(localized: "Temperatur"), selection: $temperatureUnit) {
                    Text("°C").tag("celsius")
                    Text("°F").tag("fahrenheit")
                }

                Picker(String(localized: "Windgeschwindigkeit"), selection: $windSpeedUnit) {
                    Text("km/h").tag("kmh")
                    Text("m/s").tag("ms")
                    Text("mph").tag("mph")
                    Text("kn").tag("kn")
                    Text("Bft").tag("bft")
                }

                Picker(String(localized: "Niederschlag"), selection: $precipitationUnit) {
                    Text("mm").tag("mm")
                    Text("inch").tag("inch")
                }

                Picker(String(localized: "Zeitformat"), selection: $timeFormatPreference) {
                    ForEach(TimeFormatPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
            }
            .onChange(of: temperatureUnit) { _, newValue in
                settingsService.updateTemperatureUnit(newValue)
            }
            .onChange(of: windSpeedUnit) { _, newValue in
                settingsService.updateWindSpeedUnit(newValue)
            }
            .onChange(of: precipitationUnit) { _, newValue in
                settingsService.updatePrecipitationUnit(newValue)
            }
            .onChange(of: timeFormatPreference) { _, newValue in
                settingsService.timeFormatPreference = newValue
                Task {
                    await NotificationSettingsManager.shared.syncTimeFormatPreferenceUpdate()
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
                .foregroundStyle(.white)
                .background(Color.orange)
                .clipShape(.rect(cornerRadius: 5))
            Text("Einheiten")
        }
    }
}

#Preview {
    UnitSettings()
}
