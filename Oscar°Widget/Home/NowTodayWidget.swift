//
//  NowTodayWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//
import SwiftUI
import WidgetKit

struct NowTodayEntryView: View {
    var entry: HomeProvider.Entry
    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var widgetRenderingMode
    
    var body: some View {
        VStack {
            HStack {
                Text(entry.location)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }
            HStack {
                Text(roundTemperatureString(temperature: entry.temperatureNow))
                    .font(.system(size: 45))
                    .fontWeight(.regular)
                Spacer()
            }
            HStack {
                Image(systemName: entry.icon)
                Spacer()
            }
            .padding(.bottom, 1)
            HStack {
                Text("H: \(roundTemperatureString(temperature: entry.temperatureMax))", comment: "Höchste Temperatur")
                    .font(.footnote)
                    .fontWeight(.bold)
                Text("T: \(roundTemperatureString(temperature: entry.temperatureMin))", comment: "Niedrigste Temperatur")
                    .font(.footnote)
                    .fontWeight(.bold)
                Spacer()
            }
            Spacer()
        }
        .widgetAccentable()
        .padding()
        .foregroundColor(.white)
        .background(
            entry.backgroundGradient
                .opacity(widgetRenderingMode == .accented ? 0 : 1)
        )
        .containerBackground(.clear, for: .widget)
    }
}

struct NowTodayWidget: Widget {
    let kind: String = "TodayWidget"
    
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeProvider()) { entry in
            NowTodayEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Vorhersage"))
        .description(String(localized: "Aktuelle Wetterbedingungen und Temperaturen für heute."))
        .supportedFamilies([.systemSmall])
    }
}

struct NowTodayEntryView_Previews: PreviewProvider {
    static var previews: some View {
        let previewGradient = LinearGradient(colors: [.sunriseStart, .sunnyDayEnd], startPoint: .top, endPoint: .bottom)
        NowTodayEntryView(entry: HomeEntry(date: Date(), location: "Berlin", temperatureMin: 12.0, temperatureMax: 21.0, temperatureNow: 19.0, icon: "sun.max.fill", backgroundGradient: previewGradient))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
