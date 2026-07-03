//
//  WidgetBasemapStore.swift
//  Oscar°
//
//  App-group cache of prerendered widget basemaps. The app renders them with
//  MapLibre (WidgetBasemapRenderer); the widget extension only reads — it may not
//  submit GPU work on device, so it composites radar data over these PNGs on the CPU.
//

import UIKit

/// One prerendered basemap: PNG in the app group plus the EXACT coordinate
/// rectangle MapLibre rendered (after bounds fitting), so overlays composite
/// pixel-exact via plain Web-Mercator math.
struct WidgetBasemapRecord: Codable {
    /// Camera center the snapshot was rendered for.
    let latitude: Double
    let longitude: Double
    /// Actual rendered map rectangle (post-fitting), from the snapshot's own
    /// corner-point conversion.
    let north: Double
    let south: Double
    let west: Double
    let east: Double
    /// Logical size (pt) and screen scale of the PNG.
    let width: Double
    let height: Double
    let scale: Double
    let renderedAt: Date
}

enum WidgetBasemapStore {
    static let appGroupID = "group.cloud.bolte.Oscar"

    /// Canonical logical composite sizes — the app prerenders basemaps at exactly
    /// these sizes and the widget composites + loads by the same key, so both
    /// targets MUST agree. The entry view scales up with `.fill`, so only the
    /// ASPECT has to match the widget family: systemSmall is square, systemLarge
    /// is near-square (329×345…364×382 pt across devices — a 360×170 landscape
    /// composite shipped once and got upscaled ~2× and cropped to half its width).
    static let smallCompositeSize = CGSize(width: 170, height: 170)
    static let largeCompositeSize = CGSize(width: 344, height: 360)
    static let compositeSizes = [smallCompositeSize, largeCompositeSize]

    /// Test hook: points the store at a writable directory outside the app group.
    nonisolated(unsafe) static var directoryOverride: URL?

    private static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("WidgetBasemaps", isDirectory: true)
    }

    private static func sizeKey(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    static func load(size: CGSize) -> (record: WidgetBasemapRecord, image: UIImage)? {
        guard let directory else { return nil }
        let key = sizeKey(size)
        guard let json = try? Data(contentsOf: directory.appendingPathComponent("\(key).json")),
              let record = try? JSONDecoder().decode(WidgetBasemapRecord.self, from: json),
              let png = try? Data(contentsOf: directory.appendingPathComponent("\(key).png")),
              let image = UIImage(data: png, scale: record.scale)
        else { return nil }
        return (record, image)
    }

    static func save(_ record: WidgetBasemapRecord, image: UIImage) {
        guard let directory,
              let png = image.pngData(),
              let json = try? JSONEncoder().encode(record)
        else { return }
        let key = sizeKey(CGSize(width: record.width, height: record.height))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: directory.appendingPathComponent("\(key).png"), options: .atomic)
        try? json.write(to: directory.appendingPathComponent("\(key).json"), options: .atomic)
    }
}
