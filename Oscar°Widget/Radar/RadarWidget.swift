    //
    //  RadarWidget.swift
    //  RadarWidget
    //
    //  Created by Philipp Bolte on 22.09.20.
    //
    import WidgetKit
    import SwiftUI
        
    struct RadarWidgetEntryView : View {
        var entry: RadarProvider.Entry
        @Environment(\.widgetFamily) var family

        var body: some View {
            ZStack {
                entry.image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        ZStack {
                            Circle()
                                .foregroundColor(.white)
                                .shadow(radius: 5)
                                .frame(width: 15, height: 15)
                            Circle()
                                .foregroundColor(.blue)
                                .frame(width: 10, height: 10)
                        }
                    )
                VStack {
                    HStack {
                        Text(entry.snapshotTime)
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(5)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(15)
            }
            .containerBackground(.clear, for: .widget)
        }
    }
    
    struct RadarWidget: Widget {
        let kind: String = "WeatherWidget"
        
        
        var body: some WidgetConfiguration {
            StaticConfiguration(kind: kind, provider: RadarProvider()) { entry in
                RadarWidgetEntryView(entry: entry)
            }
            .contentMarginsDisabled()
            .configurationDisplayName(String(localized: "Regenradar"))
            .description(String(localized: "Regenradar für aktuellen Standort"))
            .supportedFamilies([.systemSmall, .systemLarge])
        }
    }
    
    struct RadarWidget_Previews: PreviewProvider {
        static var previews: some View {
            RadarWidgetEntryView(entry: RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00"))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
