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
        Form {
            Section {
                Picker("Temperatur", selection: $settingsService.temperatureUnit) {
                    Text("°C").tag("celsius")
                    Text("°F").tag("fahrenheit")
                }

                Picker("Windgeschwindigkeit", selection: $settingsService.windSpeedUnit) {
                    Text("km/h").tag("kmh")
                    Text("m/s").tag("ms")
                    Text("mph").tag("mph")
                    Text("kn").tag("kn")
                    Text("Bft").tag("bft")
                }

                Picker("Niederschlag", selection: $settingsService.precipitationUnit) {
                    Text("mm").tag("mm")
                    Text("inch").tag("inch")
                }

                Picker("Zeitformat", selection: $settingsService.timeFormatPreference) {
                    ForEach(TimeFormatPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
            }
        }
        .onChange(of: settingsService.timeFormatPreference) {
                Task {
                    await NotificationSettingsManager.shared.syncTimeFormatPreferenceUpdate()
                }
        }
        .navigationTitle("Einheiten")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        UnitSettings()
    }
}
