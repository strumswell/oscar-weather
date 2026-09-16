import CoreLocation
import SwiftUI

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
