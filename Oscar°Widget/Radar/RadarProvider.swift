import WidgetKit
import SwiftUI
import MapKit

struct RadarEntry: TimelineEntry {
    let date: Date
    let image: UIImage
}

struct RadarProvider: TimelineProvider {
    let locationService = LocationService.shared
    let wmsVersion = "1.1.1"
    let zoomLevel = 1
    let radarOverlayAlpha = 0.7
    let mapColorType: UIUserInterfaceStyle = .dark
    let pixelSize = 300
    
    init() {
        locationService.update()
    }

    func placeholder(in context: Context) -> RadarEntry {
        return RadarEntry(date: Date(), image: UIImage(named: "rain")!)
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarEntry) -> Void) {
        getMapAndRadarImage(zoomLevel: zoomLevel) { image in
            let entry = RadarEntry(date: Date(), image: image)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarEntry>) -> Void) {
        getMapAndRadarImage(zoomLevel: zoomLevel) { image in
            let entry = RadarEntry(date: Date(), image: image)
            let nextUpdateDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries:[entry], policy: .after(nextUpdateDate))
            completion(timeline)
        }
    }

    func getMapAndRadarImage(zoomLevel: Int, completion: @escaping (UIImage) -> Void) {
        locationService.update()
        let location = locationService.getCoordinates()

        let region = MKCoordinateRegion.region(for: location, zoomLevel: zoomLevel)
        fetchMapSnapshot(region: region) { snapshotImage in
            guard let mapImage = snapshotImage else {
                completion(UIImage(systemName: "wifi.exclamationmark")!) // Provide an error image or default
                return
            }
            let bbox = calculateBBoxForRegion(region)
            self.fetchRadarImage(for: mapImage, with: bbox) { radarOverlayImage in
                completion(radarOverlayImage)
            }
        }
    }


    func fetchMapSnapshot(region: MKCoordinateRegion, completion: @escaping (UIImage?) -> Void) {
        let mapSnapshotOptions = MKMapSnapshotter.Options()
        mapSnapshotOptions.region = region
        mapSnapshotOptions.size = CGSize(width: pixelSize, height: pixelSize)
        mapSnapshotOptions.scale = UIScreen.main.scale
        mapSnapshotOptions.traitCollection = UITraitCollection(userInterfaceStyle: mapColorType)

        let snapshotter = MKMapSnapshotter(options: mapSnapshotOptions)
        snapshotter.start { snapshot, error in
            if let error = error {
                print("Error fetching map snapshot: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let snapshot = snapshot else {
                print("Snapshot completion is nil without error.")
                completion(nil)
                return
            }
            completion(snapshot.image)
        }
    }


    func fetchRadarImage(for mapImage: UIImage, with bbox: String, completion: @escaping (UIImage) -> Void) {
        let urlString = "https://maps.dwd.de/geoserver/dwd/wms?SERVICE=WMS&VERSION=\(wmsVersion)&REQUEST=GetMap&FORMAT=image/png8&TRANSPARENT=true&STYLES&LAYERS=dwd:Niederschlagsradar&exceptions=application/vnd.ogc.se_inimage&SRS=EPSG:4326&WIDTH=\(pixelSize)&HEIGHT=\(pixelSize)&BBOX=\(bbox)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            completion(mapImage)  // Return map image on URL failure
            return
        }
                
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching radar image: \(error.localizedDescription)")
                completion(mapImage)  // Return map image on fetch failure
                return
            }
            guard let data = data, let image = UIImage(data: data) else {
                print("Failed to load radar image data.")
                completion(mapImage)
                return
            }
            UIGraphicsBeginImageContext(mapImage.size)
            mapImage.draw(at: CGPoint.zero)
            image.draw(in: CGRect(x: 0, y: 0, width: mapImage.size.width, height: mapImage.size.height), blendMode: .normal, alpha: radarOverlayAlpha)
            let combinedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            completion(combinedImage ?? mapImage)
        }.resume()
    }
    
    func calculateBBoxForRegion(_ region: MKCoordinateRegion) -> String {
        // Calculate the corners of the map region
        let center = region.center
        let span = region.span

        let minLatitude = max(min(center.latitude - (span.latitudeDelta / 2), 90.0), -90.0)
        let maxLatitude = max(min(center.latitude + (span.latitudeDelta / 2), 90.0), -90.0)
        let minLongitude = max(min(center.longitude - (span.longitudeDelta / 2), 180.0), -180.0)
        let maxLongitude = max(min(center.longitude + (span.longitudeDelta / 2), 180.0), -180.0)

        // For WMS 1.1.1, the order is minX, minY, maxX, maxY (longitude, latitude)
        return "\(minLongitude),\(minLatitude),\(maxLongitude),\(maxLatitude)"
    }
}

extension MKCoordinateRegion {
    /// Adjusts the region size based on a zoom level (1-20, where 20 is very zoomed-in)
    static func region(for location: CLLocationCoordinate2D, zoomLevel: Int) -> MKCoordinateRegion {
        let baseMeters = 75000.0 // Starting point for zoom level 1
        let meters = baseMeters / pow(2, Double(zoomLevel - 1)) // Decrease area with increasing zoom level
        return MKCoordinateRegion(center: location, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}
