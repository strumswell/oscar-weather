    //
    //  RadarWidget.swift
    //  RadarWidget
    //
    //  Created by Philipp Bolte on 22.09.20.
    //
    import WidgetKit
    import SwiftUI
        
    struct RadarWidgetEntryView : View {
        @Environment(\.widgetRenderingMode) var widgetRenderingMode

        var entry: RadarProvider.Entry
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        var body: some View {
            ZStack(alignment: .center) {
                if #available(iOSApplicationExtension 18.0, *) {
                    Image(uiImage: entry.image)
                        .resizable()
                        .widgetAccentedRenderingMode(.accentedDesaturated)
                        .aspectRatio(contentMode: .fill)
                        .contrast(widgetRenderingMode == .accented ? 1.5 : 1)
                } else {
                    Image(uiImage: entry.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                VStack {
                    HStack {
                        Text(dateFormatter.string(from: entry.date))
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(widgetRenderingMode == .accented ? .gray.opacity(0.3) : .gray.opacity(0.6))
                            .cornerRadius(5)
                            .widgetAccentable()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(15)

                Circle()
                    .fill(.blue)
                    .widgetAccentable()
                    .frame(width: 11, height: 11)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(radius: 3)
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
            RadarWidgetEntryView(entry: RadarEntry(date: Date(), image: UIImage(named: "rain")!))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
