//
//  WMSTileOverlay.swift
//  WMSKit
//
//  Created by Erik Haider Forsen on 20/01/2017.
//  Copyright © 2017 Erik Haider Forsen. All rights reserved.
//  https://github.com/forsen/WMSKit/blob/master/WMSKit/WMSTileOverlay.swift
import Foundation
import MapKit

extension String {

    func stringByAppendingPathComponent(path: String) -> String {

        let nsSt = self as NSString

        return nsSt.appendingPathComponent(path)
    }
}


/**
 WMSTileOverlay is a subclass of MKTileOverlay. It overrides the public functions
 `url(forTilePath path: path) -> URL` and
 `loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void)`

 Downloaded tiles is cached, and cached tiles is used if they exists.
 Usage
 ----
     let overlay = WMSTileOverlay(urlArg: "https://myWmsService/enedpoint?request=GetMap?layers=..." useMercator: true, wmsVersion: "1.3.0")
     mapView.add(overlay)
 Links
 ----
 [Source](https://github.com/forsen/WMSKit/) – The source code is available at GitHub

 [CocoaPods](https://cocoapods.org/pods/WMSKit) – The podspec is hosted at CocoaPods

 [Demo project](https://github.com/forsen/WMSKitDemo/) – A demo project hostet at GitHub which demonstrates how to use this WMSKit
 */
public class WMSTileOverlay : MKTileOverlay {

    let TILE_CACHE = "TILE_CACHE"
    let enableTileCache = false
    var url: String
    var useMercator: Bool
    let wmsVersion: String
    var alpha: CGFloat = 0.5

    /**
     Initializes a WMSTileOverlay. Supported WMS version is 1.1.1 and 1.3.0

     urlArg should look something like this:

         https://yourWmsService.com/wms?request=GetMap&service=WMS&styles=default&layers=layer&version=1.3.0&CRS=EPSG:4326&width=256&height=256&format=image/png

      - parameter urlArg: A string representation of URL to WMS Service
      - parameter useMercator: True if mercator is to be used
      - parameter wmsVersion: Which wmsVersion is used
      - returns: An overlay to be used with MapKit
     */
    public init(urlArg: String, useMercator: Bool, wmsVersion: String) {
        self.url = urlArg
        self.useMercator = useMercator
        self.wmsVersion = wmsVersion
        super.init(urlTemplate: url)
    }

    func xOfColumn(column: Int, zoom: Int) -> Double {
        let x = Double(column)
        let z = Double(zoom)
        return x / pow(2.0, z) * 360.0 - 180
    }

    func yOfRow(row: Int, zoom: Int) -> Double {
        let y = Double(row)
        let z = Double(zoom)
        let n = .pi - 2.0 * .pi * y / pow(2.0, z)
        return 180.0 / .pi * atan(0.5 * (exp(n) - exp(-n)))
    }


    func mercatorXofLongitude(lon: Double) -> Double {
        return lon * 20037508.34 / 180
    }

    func mercatorYofLatitude(lat: Double) -> Double {
        var y = log(tan((90 + lat) * .pi / 360)) / (.pi / 180)
        y = y * 20037508.34 / 180
        return y
    }

    public override func url(forTilePath path: MKTileOverlayPath) -> URL {
        var left = xOfColumn(column: path.x, zoom: path.z)
        var right = xOfColumn(column: path.x+1, zoom: path.z)
        var bottom = yOfRow(row: path.y+1, zoom: path.z)
        var top = yOfRow(row: path.y, zoom: path.z)
        if(useMercator){
            left   = mercatorXofLongitude(lon: left) // minX
            right  = mercatorXofLongitude(lon: right) // maxX
            bottom = mercatorYofLatitude(lat: bottom) // minY
            top    = mercatorYofLatitude(lat: top) // maxY
        }

        var resolvedUrl = "\(self.url)"
        if(wmsVersion.contains("1.3")) {
            resolvedUrl += "&BBOX=\(bottom),\(left),\(top),\(right)"
        } else {
            resolvedUrl += "&BBOX=\(left),\(bottom),\(right),\(top)"
        }

        return URL(string: resolvedUrl)!
    }

    func tileZ(zoomScale: MKZoomScale) -> Int {
        let numTilesAt1_0 = MKMapSize.world.width / 256.0
        let zoomLevelAt1_0 = log2(Float(numTilesAt1_0))
        let zoomLevel = max(0, zoomLevelAt1_0 + floor(log2f(Float(zoomScale)) + 0.5))
        return Int(zoomLevel)
    }

    func createPathIfNecessary(path: String) -> Void {
        let fm = FileManager.default
        if(!fm.fileExists(atPath: path)) {
            do {
                try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch let error {
                print(error)
            }
        }
    }

    func cachePathWithName(name: String) -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
        let cachesPath: String = paths as String
        let cachePath = cachesPath.stringByAppendingPathComponent(path: name)
        createPathIfNecessary(path: cachesPath)
        createPathIfNecessary(path: cachePath)

        return cachePath
    }

    func getFilePathForURL(url: URL, folderName: String) -> String {
        return cachePathWithName(name: folderName).stringByAppendingPathComponent(path: "\(url.hashValue)")
    }

    func cacheUrlToLocalFolder(url: URL, data: NSData, folderName: String) {
        let localFilePath = getFilePathForURL(url: url, folderName: folderName)
        do {
            try data.write(toFile: localFilePath)
        } catch let error {
            print(error)
        }
    }

    public var applyColorTransform = false

    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url1 = self.url(forTilePath: path)
        let filePath = getFilePathForURL(url: url1, folderName: TILE_CACHE)

        let file = FileManager.default

        if file.fileExists(atPath: filePath) {
            let tileData =  try? NSData(contentsOfFile: filePath, options: .dataReadingMapped)
            if applyColorTransform, let data = tileData as Data? {
                applyColorTransformation(to: data, result: result)
            } else {
                result(tileData as Data?, nil)
            }
        } else {
            let request = NSMutableURLRequest(url: url1)
            request.httpMethod = "GET"

            let session = URLSession.shared
            session.dataTask(with: request as URLRequest, completionHandler: {(data, response, error) in

                if error != nil {
                    print("Error downloading tile")
                    result(nil, error)
                }
                else {
                    if (self.enableTileCache) {
                        do {
                            try data?.write(to: URL(fileURLWithPath: filePath))
                        } catch let error {
                            print(error)
                        }
                    }

                    if self.applyColorTransform, let data = data {
                        self.applyColorTransformation(to: data, result: result)
                    } else {
                        result(data, nil)
                    }
                }
            }).resume()
        }
    }

    private func applyColorTransformation(to data: Data, result: @escaping (Data?, Error?) -> Void) {
        guard let image = UIImage(data: data),
              let transformedImage = transformRadarColors(image: image),
              let transformedData = transformedImage.pngData() else {
            result(data, nil)
            return
        }
        result(transformedData, nil)
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
}
