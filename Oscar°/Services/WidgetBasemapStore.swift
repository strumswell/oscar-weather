//
//  WidgetBasemapStore.swift
//  Oscar°
//
//  App-group cache of prerendered widget basemaps. The app renders them with
//  MapLibre (WidgetBasemapRenderer); the widget extension only reads — it may not
//  submit GPU work on device, so it composites radar data over these PNGs on the CPU.
//

import CoreLocation
import UIKit

struct WidgetBasemapRecord: Codable {
    let latitude: Double
    let longitude: Double
    let north: Double
    let south: Double
    let west: Double
    let east: Double
    let width: Double
    let height: Double
    let scale: Double
    let renderedAt: Date
    var style: String?
}

enum WidgetBasemapStore {
    static let appGroupID = AppGroup.identifier

    static let smallCompositeSize = CGSize(width: 170, height: 170)
    static let largeCompositeSize = CGSize(width: 344, height: 360)
    static let compositeSizes = [smallCompositeSize, largeCompositeSize]

    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("WidgetBasemaps", isDirectory: true)
    }

    // MARK: - Requested styles handshake

    static let defaultStyle = "fiord"
    private static let requestedStylesKey = "radarWidgetRequestedStyles"

    static func requestedStyles() -> [String] {
        let stored = UserDefaults(suiteName: appGroupID)?
            .stringArray(forKey: requestedStylesKey) ?? []
        return stored.isEmpty ? [defaultStyle] : stored
    }

    static func registerRequestedStyle(_ style: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var styles = defaults.stringArray(forKey: requestedStylesKey) ?? []
        guard !styles.contains(style) else { return }
        styles.append(style)
        defaults.set(styles, forKey: requestedStylesKey)
    }

    private static let fixedBasemapsKey = "radarWidgetFixedBasemaps"

    static func fixedKey(style: String, at coordinate: CLLocationCoordinate2D) -> String {
        "\(style)@" + String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }

    static func parseFixedKey(_ key: String) -> (style: String, coordinate: CLLocationCoordinate2D)? {
        let parts = key.split(separator: "@")
        guard parts.count == 2 else { return nil }
        let numbers = parts[1].split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        return (String(parts[0]), CLLocationCoordinate2D(latitude: numbers[0], longitude: numbers[1]))
    }

    static func fixedKeys() -> [String] {
        UserDefaults(suiteName: appGroupID)?.stringArray(forKey: fixedBasemapsKey) ?? []
    }

    static func registerFixedBasemap(style: String, at coordinate: CLLocationCoordinate2D) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let keys = defaults.stringArray(forKey: fixedBasemapsKey) ?? []
        defaults.set(movedToEnd(fixedKey(style: style, at: coordinate), in: keys), forKey: fixedBasemapsKey)
    }

    static func movedToEnd(_ key: String, in keys: [String]) -> [String] {
        Array((keys.filter { $0 != key } + [key]).suffix(12))
    }

    // MARK: - Records

    private static func key(_ size: CGSize, style: String, fixed: CLLocationCoordinate2D? = nil) -> String {
        key(size, name: fixed.map { fixedKey(style: style, at: $0) } ?? style)
    }

    private static func key(_ size: CGSize, name: String) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))-\(name)"
    }

    private struct BasemapFile: Codable {
        let record: WidgetBasemapRecord
        let png: Data
    }

    static func load(
        size: CGSize, style: String, fixed: CLLocationCoordinate2D? = nil
    ) -> (record: WidgetBasemapRecord, image: UIImage)? {
        guard let directory else { return nil }
        let key = key(size, style: style, fixed: fixed)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).basemap")),
              let file = try? JSONDecoder().decode(BasemapFile.self, from: data),
              let image = UIImage(data: file.png, scale: file.record.scale)
        else { return nil }
        return (file.record, image)
    }

    static func save(_ record: WidgetBasemapRecord, image: UIImage, fixed: CLLocationCoordinate2D? = nil) {
        guard let directory,
              let png = image.pngData(),
              let data = try? JSONEncoder().encode(BasemapFile(record: record, png: png))
        else { return }
        let key = key(CGSize(width: record.width, height: record.height),
                      style: record.style ?? defaultStyle, fixed: fixed)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(key).basemap"), options: .atomic)
        for legacy in ["png", "json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).\(legacy)"))
        }
    }

    static func removeFixedBasemaps(except keys: [String]) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        let kept = Set(keys.flatMap { name in compositeSizes.map { "\(key($0, name: name)).basemap" } })
        for file in files where file.contains("@") && !kept.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
