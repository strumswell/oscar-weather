//
//  DailyForecastWidget.swift
//  Oscar°WidgetExtension
//
//  Multi-day forecast widget (medium / large) with a configurable city and the
//  atmospheric sky gradient used by the Now widget.
//

import CoreLocation
import SwiftUI
import WidgetKit

// MARK: - Timeline entry

// MARK: - Provider

// MARK: - Views

// MARK: - Widget

struct DailyForecastWidget: Widget {
    let kind = "DailyForecastWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectCityIntent.self,
            provider: DailyForecastProvider()
        ) { entry in
            DailyForecastEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Tagesvorhersage"))
        .description(String(localized: "Mehrtägige Vorhersage mit Temperaturverlauf."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Small", as: .systemSmall) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    DailyForecastWidget()
} timeline: {
    DailyForecastEntry.placeholder
}
