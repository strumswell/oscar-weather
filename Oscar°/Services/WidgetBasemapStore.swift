//
//  WidgetBasemapStore.swift
//  Oscar°
//
//  App-group cache of prerendered widget basemaps. The app renders them with
//  MapLibre (WidgetBasemapRenderer); the widget extension only reads — it may not
//  submit GPU work on device, so it composites radar data over these PNGs on the CPU.
//

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

    // MARK: - Records

    private static func key(_ size: CGSize, style: String) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))-\(style)"
    }

    private struct BasemapFile: Codable {
        let record: WidgetBasemapRecord
        let png: Data
    }

    static func load(size: CGSize, style: String) -> (record: WidgetBasemapRecord, image: UIImage)? {
        guard let directory else { return nil }
        let key = key(size, style: style)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(key).basemap")),
              let file = try? JSONDecoder().decode(BasemapFile.self, from: data),
              let image = UIImage(data: file.png, scale: file.record.scale)
        else { return nil }
        return (file.record, image)
    }

    static func save(_ record: WidgetBasemapRecord, image: UIImage) {
        guard let directory,
              let png = image.pngData(),
              let data = try? JSONEncoder().encode(BasemapFile(record: record, png: png))
        else { return }
        let key = key(CGSize(width: record.width, height: record.height),
                      style: record.style ?? defaultStyle)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(key).basemap"), options: .atomic)
        for legacy in ["png", "json"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).\(legacy)"))
        }
    }
}
