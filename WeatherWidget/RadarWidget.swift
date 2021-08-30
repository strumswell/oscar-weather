    //
    //  RadarWidget.swift
    //  RadarWidget
    //
    //  Created by Philipp Bolte on 22.09.20.
    //
    import WidgetKit
    import SwiftUI
    import Intents
    import MapKit
    import CoreLocation
    
    extension UIImage {
        public static func loadFrom(url: URL, completion: @escaping (_ image: UIImage?) -> ()) {
            DispatchQueue.global().async {
                if let data = try? Data(contentsOf: url) {
                    DispatchQueue.main.async {
                        completion(UIImage(data: data))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }
    }

    extension String {
        public static func loadSnapShotTime(url: URL, completion: @escaping (_ snapshotTime: String?) -> ()) {
                    let request = URLRequest(url: url)
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let data = data {
                            if let decodedResponse = try? JSONDecoder().decode(WeatherMapsResponse.self, from: data) {
                                DispatchQueue.main.async {
                                    let metadata = decodedResponse.self
                                    let epochTime = TimeInterval(metadata.radar.past[metadata.radar.past.count-1].time)
                                    let date = Date(timeIntervalSince1970: epochTime)   // "Apr 16, 2015, 2:40 AM"
                                    let formatter = DateFormatter()
                                    formatter.timeZone = .current
                                    formatter.dateFormat = "HH:mm"
                                    completion(formatter.string(from: date))
                                }
                                return
                            }
                        }
                        print("Fetch failed: \(error?.localizedDescription ?? "Unknown error")")
                        completion(nil)
                    }.resume()
            
        }
    }
    
    struct Provider: TimelineProvider {
        let locationManager = CLLocationManager()
        let defaultCoordinate = CLLocationCoordinate2D.init(latitude: 52.42, longitude: 12.52)

        func placeholder(in context: Context) -> RadarEntry {
            RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
        }
        
        func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> ()) {
            let entry = RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
            completion(entry)
        }
        
        func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> ()) {
            let currentDate = Date()
            let coordinate = locationManager.location?.coordinate ?? self.defaultCoordinate
            print(locationManager.authorizationStatus.rawValue)
            locationManager.requestAlwaysAuthorization()
            
            guard let url = URL(string: "https://radar.bolte.cloud/api/v2/mapshot?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&map=3&color=8&key=4d0ddebf-918f-495c-bc9c-fefa333a30c7") else { return }
            
            UIImage.loadFrom(url: url) { image in
                if let image = image {
                    let date = Date()
                    let img = Image(uiImage: image)
                    
                    String.loadSnapShotTime(url: URL(string: "https://api.rainviewer.com/public/weather-maps.json")!) { snapshotTime in
                        
                        let entry: RadarEntry
                        
                        if (snapshotTime != nil) {
                            entry = RadarEntry(
                                date: date,
                                image: img,
                                snapshotTime: snapshotTime!
                            )
                        } else {
                            entry = RadarEntry(
                                date: date,
                                image: img,
                                snapshotTime: ""
                            )
                        }
                        
                        let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: date)!
                        
                        let timeline = Timeline(
                            entries:[entry],
                            policy: .after(nextUpdateDate)
                        )
                        
                        completion(timeline)
                    }
                } else {
                    let entry = RadarEntry(date: currentDate, image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
                    let timeline = Timeline(entries: [entry], policy: .atEnd)
                    completion(timeline)
                }
            }
        }
    }
    
    struct RadarEntry: TimelineEntry {
        let date: Date
        let image: Image
        let snapshotTime: String
    }
    
    struct RadarWidgetEntryView : View {
        var entry: Provider.Entry
        
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
        }
    }
    
    struct RadarWidget: Widget {
        let kind: String = "WeatherWidget"
        
        var body: some WidgetConfiguration {
            StaticConfiguration(kind: kind, provider: Provider()) { entry in
                RadarWidgetEntryView(entry: entry)
            }
            .configurationDisplayName("Regenradar")
            .description("Regenradar für aktuellen Standort")
        }
    }
    
    struct RadarWidget_Previews: PreviewProvider {
        static var previews: some View {
            RadarWidgetEntryView(entry: RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00"))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
        }
    }
