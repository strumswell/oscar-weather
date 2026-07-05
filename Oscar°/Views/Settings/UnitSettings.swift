//
//  UnitSettings.swift
//  Oscar°
//
//  Created by Philipp Bolte on 06.07.24.
//

import SwiftUI

struct UnitSettings: View {
    // Units are plain @Observable properties on the service (mirrored out of Core
    // Data), so the pickers bind straight to it and persistence lives in the didSets.
    @Bindable private var settingsService = SettingService.shared

    var body: some View {
        NavigationStack {
            List {
                Picker(String(localized: "Temperatur"), selection: $settingsService.temperatureUnit) {
                    Text("°C").tag("celsius")
                    Text("°F").tag("fahrenheit")
                }

                Picker(String(localized: "Windgeschwindigkeit"), selection: $settingsService.windSpeedUnit) {
                    Text("km/h").tag("kmh")
                    Text("m/s").tag("ms")
                    Text("mph").tag("mph")
                    Text("kn").tag("kn")
                    Text("Bft").tag("bft")
                }

                Picker(String(localized: "Niederschlag"), selection: $settingsService.precipitationUnit) {
                    Text("mm").tag("mm")
                    Text("inch").tag("inch")
                }

                Picker(String(localized: "Zeitformat"), selection: $settingsService.timeFormatPreference) {
                    ForEach(TimeFormatPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
            }
            .onChange(of: settingsService.timeFormatPreference) {
                Task {
                    await NotificationSettingsManager.shared.syncTimeFormatPreferenceUpdate()
                }
            }
        }
        .navigationTitle("Einheiten")
        .navigationBarTitleDisplayMode(.inline)
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
