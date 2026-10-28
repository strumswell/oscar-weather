import CoreLocation
import SwiftUI

struct StormCellInfoSheet: View {
    let cell: StormCellInfo
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
                .overlay { Circle().stroke(.white.opacity(0.8), lineWidth: 1) }
            Text(intensity.label)
                .font(.headline)
            Spacer()
            Text(units.rateString(cell.peakMmh))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            row(label: "Mittlere Intensität", value: units.rateString(cell.meanMmh))
            Divider().padding(.leading, 16)
            row(label: "Fläche", value: units.areaString(cell.areaKm2))
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
        switch cell.peakMmh {
        case ..<2: ("Leichter Schauer", Color(hex: 0x00CACA))
        case ..<10: ("Mäßiger Schauer", Color(hex: 0xFFFF00))
        case ..<50: ("Starker Schauer", Color(hex: 0xFF0000))
        default: ("Extremer Schauer", Color(hex: 0xFE33FF))
        }
    }

    private var movement: String {
        guard cell.velocityKmh >= 3 else { return String(localized: "nahezu stationär") }
        let bearing = (cell.bearingDeg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return "\(compassDirection(bearing)) · \(units.windString(cell.velocityKmh))"
    }

    private var arrival: String? {
        guard let referenceCoordinate,
              let approach = cell.closestApproach(to: referenceCoordinate),
              cell.velocityKmh >= 3 else { return nil }
        guard approach.distanceKm <= cell.radiusKm + 5 else {
            guard approach.distanceKm <= cell.radiusKm + 30 else { return nil }
            if let referenceName {
                return String(localized: "Zieht voraussichtlich an \(referenceName) vorbei.")
            }
            return String(localized: "Zieht voraussichtlich an deinem Standort vorbei.")
        }
        guard approach.minutes > 1 else {
            if let referenceName {
                return String(localized: "Befindet sich etwa über \(referenceName).")
            }
            return String(localized: "Befindet sich etwa über deinem Standort.")
        }
        let eta = SettingService.formattedTime(Date().addingTimeInterval(approach.minutes * 60))
        if let referenceName {
            return String(localized: "Erreicht \(referenceName) gegen \(eta).")
        }
        return String(localized: "Erreicht deinen Standort gegen \(eta).")
    }

    private var units: Units { SettingService.shared.units }
}
