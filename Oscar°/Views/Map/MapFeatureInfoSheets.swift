//
//  MapFeatureInfoSheets.swift
//  Oscar°
//
//  Tap-through detail sheets for the weather map's data overlays: DWD warning
//  polygons (Wetterwarnungen) and tracked precipitation cells (Regenzellen).
//  The models are parsed from the map features' GeoJSON attributes in
//  WeatherMapView; the sheets present like the Kartenebenen picker (glass,
//  medium detent).
//

import CoreLocation
import SwiftUI
import UIKit
import simd

// MARK: - Models

/// One active warning, parsed from an `oscar-alert-fill` feature's attributes
/// (the `/weather-alerts/area` GeoJSON properties).
struct WeatherAlertInfo: Identifiable {
    let id: String
    /// Ingesting agency: "dwd" (Germany) or "nws" (US); nil from servers that
    /// predate the field. Drives attribution and severity terminology.
    let source: String?
    let event: String
    let severityRank: Int
    let headline: String?
    let details: String?
    let instruction: String?
    let onset: Date?
    let expires: Date?

    init?(attributes: [String: Any]) {
        guard let id = attributes["id"] as? String,
              let event = attributes["event"] as? String else { return nil }
        self.id = id
        self.event = event
        source = attributes["source"] as? String
        severityRank = attributes["severity_rank"] as? Int ?? 1
        headline = attributes["headline"] as? String
        details = attributes["description"] as? String
        instruction = attributes["instruction"] as? String
        onset = Self.date(attributes["onset_at"])
        expires = Self.date(attributes["expires_at"])
    }

    private static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        guard let string = value as? String else { return nil }
        return parseFrameDate(string)
    }
}

/// One tracked cell from `/radar/{region}/cells` — everything the overlay and the
/// tap sheet need, including the projected track and the footprint hull.
struct StormCellInfo: Identifiable {
    let id: Int
    let center: CLLocationCoordinate2D
    let areaKm2: Double
    let peakMmh: Double
    let meanMmh: Double
    let velocityKmh: Double
    let bearingDeg: Double
    /// Extrapolated centroids at +15/+30/+45/+60 min.
    let path: [CLLocationCoordinate2D]
    /// Convex-hull outline (closed ring); empty when the server sent none.
    let footprint: [CLLocationCoordinate2D]

    /// Equivalent circular radius — the footprint scale for cones and ETA slop.
    var radiusKm: Double { (areaKm2 / .pi).squareRoot() }

    /// Nearest approach of the projected track (center → +60 min) to `target`:
    /// minutes along the track and the miss distance. nil when there is no track.
    func closestApproach(to target: CLLocationCoordinate2D) -> (minutes: Double, distanceKm: Double)? {
        let points = [center] + path
        guard points.count >= 2 else { return nil }
        let cosLat = max(0.2, cos(target.latitude * .pi / 180))
        // Local km plane centered on the target.
        let local = points.map { point in
            SIMD2((point.longitude - target.longitude) * 111.320 * cosLat,
                  (point.latitude - target.latitude) * 110.574)
        }
        var best: (minutes: Double, distanceKm: Double)?
        for i in 0..<(local.count - 1) {
            let a = local[i], b = local[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, -simd_dot(a, ab) / lengthSquared)) : 0
            let distance = simd_length(a + ab * t)
            let minutes = 15 * (Double(i) + t)
            if best == nil || distance < best!.distanceKm {
                best = (minutes, distance)
            }
        }
        return best
    }
}

// MARK: - DWD severity styling

enum AlertSeverityStyle {
    /// DWD ranks: 1 Minor, 2 Moderate, 3 Severe, 4 Extreme — same colors as the
    /// map polygons (`syncAlertPolygons`).
    static func color(rank: Int) -> Color {
        switch rank {
        case 2: .orange
        case 3: .red
        case 4: .purple
        default: .yellow
        }
    }

    static func label(rank: Int, source: String? = nil) -> LocalizedStringKey {
        // NWS and CWA alerts both use the CAP severity terms (Minor/Moderate/Severe/
        // Extreme); the DWD warning-level names are DWD-specific.
        if source == "nws" || source == "cwa" {
            return switch rank {
            case 1: "Minor"
            case 2: "Moderate"
            case 3: "Severe"
            case 4: "Extreme"
            default: "Alert"
            }
        }
        return switch rank {
        case 2: "Markante Wetterwarnung"
        case 3: "Unwetterwarnung"
        case 4: "Extreme Unwetterwarnung"
        default: "Wetterwarnung"
        }
    }

    static func sourceName(_ source: String?) -> String {
        switch source {
        case "nws": "NOAA / National Weather Service"
        case "cwa": "CWA / Central Weather Administration"
        default: "Deutscher Wetterdienst"
        }
    }
}

// MARK: - Warning sheet

/// All warnings under the tapped point, most severe first — presented small like
/// the Kartenebenen sheet, pullable to .large for long official texts.
struct AlertInfoSheet: View {
    let alerts: [WeatherAlertInfo]
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(alerts) { alert in
                        AlertInfoCard(alert: alert)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle(alerts.count == 1 ? Text("Wetterwarnung") : Text("Wetterwarnungen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismissSheet() })
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
    }
}

private struct AlertInfoCard: View {
    let alert: WeatherAlertInfo

    private var severityColor: Color { AlertSeverityStyle.color(rank: alert.severityRank) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(AlertSeverityStyle.label(rank: alert.severityRank, source: alert.source))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(severityColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(severityColor.opacity(0.16), in: Capsule())
                Spacer()
                Text("Stufe \(alert.severityRank)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(alert.headline ?? alert.event)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let validity {
                Label(validity, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let details = alert.details, !details.isEmpty {
                Text(details)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let instruction = alert.instruction, !instruction.isEmpty {
                Divider()
                Text(instruction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Quelle: \(AlertSeverityStyle.sourceName(alert.source))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var validity: String? {
        switch (alert.onset, alert.expires) {
        case let (onset?, expires?):
            return "\(SettingService.formattedDateTime(onset)) – \(SettingService.formattedDateTime(expires))"
        case let (nil, expires?):
            return String(localized: "Bis \(SettingService.formattedDateTime(expires))")
        case let (onset?, nil):
            return String(localized: "Ab \(SettingService.formattedDateTime(onset))")
        default:
            return nil
        }
    }
}

// MARK: - Storm cell sheet

/// Details for one tapped Regenzelle: intensity, size, movement — and when the
/// projected track passes the selected location, the estimated arrival time.
struct StormCellInfoSheet: View {
    let cell: StormCellInfo
    /// The selected location the ETA line refers to (NowView's active city).
    var referenceCoordinate: CLLocationCoordinate2D?
    var referenceName: String?
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intensityHeader
                    detailRows
                    arrivalSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle(Text("Regenzelle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismissSheet() })
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
    }

    private var intensityHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(intensity.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            Text(intensity.label)
                .font(.headline)
            Spacer()
            Text("\(formatted(cell.peakMmh)) mm/h")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            row(label: "Mittlere Intensität", value: "\(formatted(cell.meanMmh)) mm/h")
            Divider().padding(.leading, 16)
            row(label: "Fläche", value: "\(Int(cell.areaKm2.rounded())) km²")
            Divider().padding(.leading, 16)
            row(label: "Zugrichtung", value: movement)
        }
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var arrivalSection: some View {
        if let arrival {
            Label {
                Text(arrival)
                    .font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func row(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var intensity: (label: LocalizedStringKey, color: Color) {
        // Same steps as the map markers / StormCellLegend.
        switch cell.peakMmh {
        case ..<2: ("Leichter Schauer", Color(hex: 0x00CACA))
        case ..<10: ("Mäßiger Schauer", Color(hex: 0xFFFF00))
        case ..<50: ("Starker Schauer", Color(hex: 0xFF0000))
        default: ("Extremer Schauer", Color(hex: 0xFE33FF))
        }
    }

    private var movement: String {
        guard cell.velocityKmh >= 3 else { return String(localized: "nahezu stationär") }
        return "\(compassDirection) · \(Int(cell.velocityKmh.rounded())) km/h"
    }

    /// 8-way compass word for the movement direction ("toward").
    private var compassDirection: String {
        let names = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let normalizedBearing = cell.bearingDeg.truncatingRemainder(dividingBy: 360) + 360
        let index = Int(((normalizedBearing.truncatingRemainder(dividingBy: 360) + 22.5) / 45).rounded(.down)) % 8
        return names[index]
    }

    private var arrival: String? {
        guard let referenceCoordinate,
              let approach = cell.closestApproach(to: referenceCoordinate),
              cell.velocityKmh >= 3 else { return nil }
        let name = referenceName ?? String(localized: "deinen Standort")
        guard approach.distanceKm <= cell.radiusKm + 5 else {
            return String(localized: "Zieht voraussichtlich an \(name) vorbei.")
        }
        let eta = Date().addingTimeInterval(approach.minutes * 60)
        guard approach.minutes > 1 else {
            return String(localized: "Befindet sich etwa über \(name).")
        }
        return String(localized: "Erreicht \(name) gegen \(SettingService.formattedTime(eta)).")
    }

    private func formatted(_ value: Double) -> String {
        value >= 10
            ? String(Int(value.rounded()))
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}
