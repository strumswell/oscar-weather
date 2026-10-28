//
//  UnitSettings.swift
//  Oscar°
//
//  Created by Philipp Bolte on 06.07.24.
//

import SwiftUI

struct UnitSettings: View {
    @Bindable private var settingsService = SettingService.shared

    var body: some View {
        Form {
            Section {
                Picker("Temperatur", selection: $settingsService.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                Picker("Windgeschwindigkeit", selection: $settingsService.windSpeedUnit) {
                    ForEach(WindSpeedUnit.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                Picker("Niederschlag", selection: $settingsService.precipitationUnit) {
                    ForEach(PrecipitationUnit.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                Picker("Luftdruck", selection: $settingsService.pressureUnit) {
                    ForEach(PressureUnit.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                Picker("Entfernung", selection: $settingsService.distanceUnit) {
                    ForEach(DistanceUnit.allCases) { Text(verbatim: $0.symbol).tag($0) }
                }
                Picker("Zeitformat", selection: $settingsService.timeFormatPreference) {
                    ForEach(TimeFormatPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
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
