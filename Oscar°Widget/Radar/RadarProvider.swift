//
//  RadarProvider.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 10.04.23.
//

import Foundation
import CoreLocation
import SwiftUI
import WidgetKit

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

struct RadarEntry: TimelineEntry {
    let date: Date
    let image: Image
    let snapshotTime: String
}

struct RadarProvider: TimelineProvider {
    var lm: LocationManager
    let defaultCoordinate = CLLocationCoordinate2D.init(latitude: 52.42, longitude: 12.52)

    init() {
        lm = LocationManager()
        lm.update()
    }


    func placeholder(in context: Context) -> RadarEntry {
        RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
    }
    
    func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> ()) {
        let entry = RadarEntry(date: Date(), image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> ()) {
        lm.update()
        let currentDate = Date()
        let coordinate = lm.gpsLocation ?? self.defaultCoordinate
        
        guard let url = URL(string: "https://api.oscars.love/api/v1/mapshots/radar?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)") else { return }
        
        UIImage.loadFrom(url: url) { image in
            if let image = image {
                let date = Date()
                let formatter = DateFormatter()
                formatter.timeZone = .current
                formatter.dateFormat = "HH:mm"
                
                let formattedTime = formatter.string(from: date)
                let img = Image(uiImage: image)
                
                let entry = RadarEntry(date: date, image: img, snapshotTime: formattedTime)
                let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: date)!
                let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
                completion(timeline)
            } else {
                let entry = RadarEntry(date: currentDate, image: Image(uiImage: UIImage(named: "rain")!), snapshotTime: "12:00")
                let timeline = Timeline(entries: [entry], policy: .atEnd)
                completion(timeline)
            }
        }
    }
}
