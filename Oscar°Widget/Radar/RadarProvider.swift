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
        let urlString = "https://maps.dwd.de/geoserver/dwd/wms?SERVICE=WMS&VERSION=\(wmsVersion)&REQUEST=GetMap&FORMAT=image/png8&TRANSPARENT=true&STYLES&LAYERS=dwd:RADOLAN-RY&exceptions=application/vnd.ogc.se_inimage&SRS=EPSG:4326&WIDTH=\(pixelSize)&HEIGHT=\(pixelSize)&BBOX=\(bbox)"
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
            guard let data = data, var image = UIImage(data: data) else {
                print("Failed to load radar image data.")
                completion(mapImage)
                return
            }

            // Apply color transformation
            if let transformedImage = self.transformRadarColors(image: image) {
                image = transformedImage
            }

            UIGraphicsBeginImageContext(mapImage.size)
            mapImage.draw(at: CGPoint.zero)
            image.draw(in: CGRect(x: 0, y: 0, width: mapImage.size.width, height: mapImage.size.height), blendMode: .normal, alpha: radarOverlayAlpha)
            let combinedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            completion(combinedImage ?? mapImage)
        }.resume()
    }

    private func transformRadarColors(image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Enable high-quality interpolation
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Transform each pixel
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]
            let a = pixelData[i + 3]

            // Skip transparent pixels
            guard a > 10 else { continue }

            let transformed = transformColor(r: r, g: g, b: b, a: a)
            pixelData[i] = transformed.r
            pixelData[i + 1] = transformed.g
            pixelData[i + 2] = transformed.b
            pixelData[i + 3] = transformed.a
        }

        guard let outputCGImage = context.makeImage() else {
            return nil
        }
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private func transformColor(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let rf = CGFloat(r) / 255.0
        let gf = CGFloat(g) / 255.0
        let bf = CGFloat(b) / 255.0

        var newR: CGFloat = rf
        var newG: CGFloat = gf
        var newB: CGFloat = bf

        // NEW SCHEME → OLD SCHEME COLOR MAPPING
        // Based on extracted color values from both legends

        // Detect very pale/white colors (lowest rainfall 0.1-1 mm/24h)
        if rf > 0.95 && gf > 0.95 && bf > 0.75 {
            // Very pale yellow → Darker blue
            newR = 0.45
            newG = 0.55
            newB = 0.85
        }
        // Light yellow (1-5 mm/24h) → Blue-purple range
        else if rf > 0.85 && gf > 0.80 && bf < 0.65 {
            let yellowness = (rf + gf) / 2.0 - bf
            newR = 0.30 - yellowness * 0.10
            newG = 0.35 - yellowness * 0.10
            newB = 0.78 + yellowness * 0.05
        }
        // Yellow to yellow-green (5-10 mm/24h) → Blue
        else if rf > 0.70 && gf > 0.75 && bf < 0.50 {
            newR = 0.20
            newG = 0.39
            newB = 0.86
        }
        // Green to lime (10-15 mm/24h) → Cyan-blue
        else if gf > 0.70 && rf < 0.75 && rf > 0.45 && bf < 0.50 {
            newR = 0.20
            newG = 0.59
            newB = 0.78
        }
        // Cyan to turquoise (15-20 mm/24h) → Green-cyan
        else if bf > 0.65 && gf > 0.65 && rf < 0.55 {
            newR = 0.31
            newG = 0.78
            newB = 0.59
        }
        // Light blue (20-30 mm/24h) → Yellow-green
        else if bf > 0.70 && gf > 0.45 && gf < 0.70 && rf < 0.40 {
            newR = 0.78
            newG = 0.86
            newB = 0.39
        }
        // Blue to dark blue (30-50 mm/24h) → Orange
        else if bf > 0.65 && gf < 0.50 && rf < 0.35 {
            newR = 1.0
            newG = 0.71
            newB = 0.31
        }
        // Purple (50-80 mm/24h) → Orange-red
        else if rf > 0.40 && rf < 0.60 && bf > 0.55 && gf < 0.45 {
            newR = 1.0
            newG = 0.47
            newB = 0.24
        }
        // Magenta/pink (80-100 mm/24h) → Red
        else if rf > 0.65 && bf > 0.45 && gf < 0.50 {
            newR = 0.86
            newG = 0.24
            newB = 0.24
        }
        // Red (100-150 mm/24h) → Red (keep similar)
        else if rf > 0.75 && gf < 0.40 && bf < 0.40 {
            newR = 0.86
            newG = 0.24
            newB = 0.24
        }
        // Dark red to brown (150+ mm/24h) → Purple/magenta
        else if rf > 0.45 && rf < 0.75 && gf < 0.35 && bf < 0.40 {
            newR = 0.59
            newG = 0.20
            newB = 0.47
        }
        // Very dark (200+ mm/24h) → Dark purple
        else if rf < 0.55 && gf < 0.35 && bf < 0.40 && (rf + gf + bf) < 0.9 {
            newR = 0.47
            newG = 0.16
            newB = 0.39
        }

        // Clamp values
        newR = max(0, min(1, newR))
        newG = max(0, min(1, newG))
        newB = max(0, min(1, newB))

        return (
            r: UInt8(newR * 255.0),
            g: UInt8(newG * 255.0),
            b: UInt8(newB * 255.0),
            a: a
        )
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
