//
//  WidgetCityIntent.swift
//  Oscar°
//
//  The configurable-city options and intent for the DailyForecastWidget.
//

import AppIntents
import CoreData
import Foundation
import WidgetKit

// MARK: - Configurable city

struct WidgetCityOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let cities = [WidgetCity.currentLocation] + WidgetCityStore.savedCities()
        let items = cities.map { city in
            IntentItem(city.id, title: "\(city.name)")
        }

        return IntentItemCollection {
            IntentItemSection(items: items)
        }
    }

    func defaultResult() async -> String? {
        WidgetCity.currentLocationID
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Ort wählen"
    static let description = IntentDescription("Wähle den Ort für die Tagesvorhersage.")

    @Parameter(title: "Ort", optionsProvider: WidgetCityOptionsProvider())
    var city: String?
}
