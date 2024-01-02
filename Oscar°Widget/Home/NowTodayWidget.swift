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
    
    var body: some View {
        VStack {
            HStack {
                Text(entry.location)
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
            }
            HStack {
                Text("\(entry.temperatureNow, specifier: "%.0f")°")
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
                Text("H: \(entry.temperatureMax, specifier: "%.0f")°")
                    .font(.footnote)
                    .fontWeight(.bold)
                Text("T: \(entry.temperatureMin, specifier: "%.0f")°")
                    .font(.footnote)
                    .fontWeight(.bold)
                Spacer()
            }
            Spacer()
        }
        .padding()
        .foregroundColor(.white)
        .background(
            LinearGradient(colors: [
                entry.backgroundGradients.first!,
                entry.backgroundGradients.last!,
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}

struct NowTodayWidget: Widget {
    let kind: String = "Weather21Widget"
    
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeProvider()) { entry in
            NowTodayEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Vorhersage")
        .description("Aktuelle Wetterbedingungen und Temperaturen für heute.")
        .supportedFamilies([.systemSmall])
    }
}

struct NowTodayEntryView_Previews: PreviewProvider {
    static var previews: some View {
        NowTodayEntryView(entry: HomeEntry(date: Date(), location: "Leipzig", temperatureMin: 12.0, temperatureMax: 21.0, temperatureNow: 19.0, icon: "sun.max.fill", precipitation: 0.0, precipitationProbability: 12, backgroundGradients: [.sunriseStart, .sunnyDayEnd]))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
