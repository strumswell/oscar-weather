//
//  MapValueBubbles.swift
//  Oscar°
//
//  City value bubbles for the model temperature/wind layers: curated city list,
//  grid sampling, unit formatting, and the bubble icon artwork.
//

import UIKit

enum MapValueBubbles {
    static func windLabel(metersPerSecond: Double, unit: String) -> String {
        switch WindSpeedUnit(settingValue: unit) {
        case .kmh: return "\(Int((metersPerSecond * 3.6).rounded()))"
        case .ms:  return "\(Int(metersPerSecond.rounded()))"
        case .mph: return "\(Int((metersPerSecond * 2.23694).rounded()))"
        case .kn:  return "\(Int((metersPerSecond * 1.94384).rounded()))"
        case .bft: return "\(BeaufortScale.force(forKilometersPerHour: metersPerSecond * 3.6))"
        }
    }

    /// Nearest grid index at a coordinate (0 / outside → nil). UV via the
    /// mercator-aligned image bounds, like the render quad.
    static func sampleGridIndex(
        payload: RadarGridPayload, bounds: OscarRadarBounds, lat: Double, lon: Double
    ) -> UInt8? {
        guard payload.width > 1, payload.height > 1,
              lat < bounds.north, lat > bounds.south,
              bounds.east > bounds.west else { return nil }
        let x = (lon - bounds.west) / (bounds.east - bounds.west)
        guard x >= 0, x <= 1 else { return nil }
        let yNorth = WebMercator.projectedY(latitude: bounds.north)
        let ySouth = WebMercator.projectedY(latitude: bounds.south)
        let y = (yNorth - WebMercator.projectedY(latitude: lat)) / (yNorth - ySouth)
        guard y >= 0, y <= 1 else { return nil }
        let px = Int((x * Double(payload.width - 1)).rounded())
        let py = Int((y * Double(payload.height - 1)).rounded())
        let index = payload.indices[py * payload.width + px]
        return index > 0 ? index : nil
    }

    /// 28 pt circle in the palette color with a white ring — the label renders
    /// on top via the symbol layer's text.
    static func bubbleImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1), blur: 2,
                color: UIColor.black.withAlphaComponent(0.3).cgColor)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 27, height: 27)).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.withAlphaComponent(0.9).setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 27, height: 27))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    /// Curated city set: rank tiers gate visibility by zoom (0 = metropolis,
    /// shown first; 2 = only zoomed in). European density favors the ICON-D2
    /// wedge; the world set is for GFS.
    static let bubbleCities: [(lat: Double, lon: Double, rank: Int)] = [
        // DACH + central Europe (ICON-D2 wedge)
        (52.52, 13.41, 0), (53.55, 10.00, 1), (48.14, 11.58, 0), (50.94, 6.96, 1),
        (50.11, 8.68, 1), (48.78, 9.18, 1), (51.34, 12.37, 2), (51.05, 13.74, 2),
        (52.37, 9.73, 2), (49.45, 11.08, 2), (53.08, 8.81, 2), (51.46, 7.01, 2),
        (48.21, 16.37, 0), (47.07, 15.44, 2), (47.80, 13.04, 2), (47.27, 11.40, 2),
        (47.37, 8.54, 1), (46.20, 6.14, 1), (47.56, 7.59, 2), (46.95, 7.44, 2),
        (45.46, 9.19, 1), (45.07, 7.69, 1), (45.44, 12.32, 2), (44.41, 8.93, 2),
        (44.49, 11.34, 2), (43.77, 11.25, 1), (50.08, 14.44, 1), (49.20, 16.61, 2),
        (52.37, 4.90, 0), (51.92, 4.48, 2), (50.85, 4.35, 1), (51.22, 4.40, 2),
        (49.61, 6.13, 2), (48.86, 2.35, 0), (45.76, 4.84, 1), (48.57, 7.75, 2),
        (50.63, 3.07, 2), (44.84, -0.58, 1), (43.60, 1.44, 1), (43.30, 5.37, 1),
        (43.70, 7.27, 2), (55.68, 12.57, 1), (56.16, 10.20, 2), (57.71, 11.97, 1),
        (55.60, 13.00, 2), (50.06, 19.94, 1), (51.11, 17.03, 2), (52.41, 16.93, 2),
        (54.35, 18.65, 2), (47.50, 19.04, 1), (48.15, 17.11, 2), (46.06, 14.51, 2),
        (45.81, 15.98, 1), (43.86, 18.41, 2), (51.51, -0.13, 0), (52.48, -1.90, 2),
        (53.48, -2.24, 1), (55.95, -3.19, 1),
        // DACH densification (zoomed-in ICON-D2 use)
        (51.23, 6.78, 2), (51.51, 7.47, 2), (51.96, 7.63, 2), (54.32, 10.14, 2),
        (54.09, 12.10, 2), (52.13, 11.62, 2), (50.98, 11.03, 2), (51.31, 9.49, 2),
        (48.00, 7.85, 2), (49.01, 8.40, 2), (49.49, 8.47, 2), (49.24, 6.99, 2),
        (49.01, 12.10, 2), (49.79, 9.95, 2), (48.40, 9.99, 2), (50.78, 6.08, 2),
        (52.02, 8.53, 2), (52.27, 10.52, 2), (52.28, 8.05, 2), (53.87, 10.69, 2),
        (50.83, 12.92, 2), (48.31, 14.29, 2), (46.62, 14.31, 2), (47.50, 9.75, 2),
        (46.00, 8.95, 2), (47.42, 9.37, 2), (46.52, 6.63, 2), (46.85, 9.53, 2),
        // Wider Europe densification
        (52.09, 5.12, 2), (51.44, 5.47, 2), (47.22, -1.55, 2), (43.61, 3.88, 2),
        (45.19, 5.72, 2), (40.85, 14.27, 1), (38.12, 13.36, 2), (45.44, 10.99, 2),
        (39.47, -0.38, 2), (37.39, -5.99, 1), (41.15, -8.61, 2), (43.26, -2.93, 2),
        (41.65, -0.88, 2), (55.86, -4.25, 2), (51.45, -2.59, 2), (54.98, -1.61, 2),
        (60.39, 5.32, 2), (63.43, 10.40, 2), (69.65, 18.96, 2), (28.12, -15.43, 2),
        (54.69, 25.28, 2), (56.95, 24.11, 1), (59.44, 24.75, 2), (53.90, 27.56, 1),
        (49.84, 24.03, 2), (46.48, 30.73, 2), (42.70, 23.32, 1), (40.64, 22.94, 2),
        // World (GFS)
        (40.71, -74.01, 0), (34.05, -118.24, 0), (41.88, -87.63, 1), (29.76, -95.37, 1),
        (25.76, -80.19, 1), (39.74, -104.99, 2), (47.61, -122.33, 1), (37.77, -122.42, 1),
        (43.65, -79.38, 1), (49.28, -123.12, 2), (45.50, -73.57, 2), (19.43, -99.13, 0),
        (4.71, -74.07, 2), (-12.05, -77.04, 1), (-33.45, -70.67, 1), (-23.55, -46.63, 0),
        (-34.60, -58.38, 0), (-22.91, -43.17, 1), (64.15, -21.94, 2), (53.35, -6.26, 1),
        (38.72, -9.14, 1), (40.42, -3.70, 0), (41.39, 2.17, 1), (41.90, 12.50, 0),
        (37.98, 23.73, 1), (41.01, 28.98, 0), (59.91, 10.75, 1), (59.33, 18.07, 0),
        (60.17, 24.94, 1), (52.23, 21.01, 0), (50.45, 30.52, 1), (44.43, 26.10, 1),
        (44.79, 20.46, 2), (55.76, 37.62, 0), (30.04, 31.24, 0), (6.52, 3.38, 1),
        (-1.29, 36.82, 2), (-26.20, 28.05, 1), (-33.92, 18.42, 2), (33.57, -7.59, 2),
        (36.75, 3.06, 2), (36.81, 10.17, 2), (32.08, 34.78, 2), (25.20, 55.27, 1),
        (24.71, 46.68, 1), (35.69, 51.39, 1), (24.86, 67.00, 1), (19.08, 72.88, 0),
        (28.61, 77.21, 0), (23.81, 90.41, 2), (13.76, 100.50, 1), (1.35, 103.82, 0),
        (-6.21, 106.85, 1), (22.32, 114.17, 1), (31.23, 121.47, 0), (39.90, 116.41, 0),
        (37.57, 126.98, 0), (35.68, 139.69, 0), (25.03, 121.57, 2), (14.60, 120.98, 2),
        (-33.87, 151.21, 0), (-37.81, 144.96, 1), (-31.95, 115.86, 2), (-36.85, 174.76, 2),
        (61.22, -149.90, 2), (21.31, -157.86, 2),
        // World densification
        (33.45, -112.07, 2), (32.78, -96.80, 1), (33.75, -84.39, 1), (42.36, -71.06, 1),
        (39.95, -75.17, 2), (38.91, -77.04, 1), (44.98, -93.27, 2), (29.95, -90.07, 2),
        (40.76, -111.89, 2), (36.17, -115.14, 2), (32.72, -117.16, 2), (51.05, -114.07, 2),
        (23.11, -82.37, 2), (8.98, -79.52, 2), (10.49, -66.88, 2), (-0.18, -78.47, 2),
        (-16.49, -68.15, 2), (-15.79, -47.88, 2), (-8.05, -34.88, 2), (-3.12, -60.02, 2),
        (-34.90, -56.19, 2), (5.56, -0.20, 2), (14.72, -17.47, 2), (9.01, 38.75, 2),
        (-6.79, 39.21, 2), (15.59, 32.53, 2), (-4.32, 15.31, 2), (-8.84, 13.23, 2),
        (33.31, 44.37, 1), (25.29, 51.53, 2), (29.38, 47.99, 2), (41.30, 69.24, 2),
        (43.24, 76.89, 2), (56.84, 60.61, 2), (55.03, 82.92, 2), (43.12, 131.89, 2),
        (47.89, 106.91, 2), (30.57, 104.07, 1), (34.34, 108.94, 2), (23.13, 113.26, 1),
        (30.59, 114.31, 2), (21.03, 105.85, 1), (10.82, 106.63, 1), (11.56, 104.92, 2),
        (16.87, 96.20, 2), (3.14, 101.69, 1), (6.93, 79.85, 2), (13.08, 80.27, 1),
        (22.57, 88.36, 1), (17.38, 78.49, 2), (12.97, 77.59, 1), (34.69, 135.50, 1),
        (43.06, 141.35, 2), (33.59, 130.40, 2), (35.18, 129.08, 2), (-27.47, 153.03, 1),
        (-34.93, 138.60, 2), (-12.46, 130.84, 2),
    ]
}
