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

    public override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url1 = self.url(forTilePath: path)
        let filePath = getFilePathForURL(url: url1, folderName: TILE_CACHE)

        let file = FileManager.default

        if file.fileExists(atPath: filePath) {
            let tileData =  try? NSData(contentsOfFile: filePath, options: .dataReadingMapped)
            result(tileData as Data?, nil)
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
                    result(data, nil)
                }
            }).resume()
        }
    }
}
