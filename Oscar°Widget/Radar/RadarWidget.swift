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
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        var body: some View {
            ZStack(alignment: .center) {
                Image(uiImage: entry.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                VStack {
                    HStack {
                        Text(dateFormatter.string(from: entry.date))
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

                Circle()
                    .fill(Color.blue)
                    .frame(width: 11, height: 11)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
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
