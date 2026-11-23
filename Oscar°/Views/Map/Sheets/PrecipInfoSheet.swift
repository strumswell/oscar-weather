import SwiftUI

struct PrecipInfoSheet: View {
    let tap: PrecipTap
    @State private var series: PrecipSeriesResponse?
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    detailRows
                    changeRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle(Text("Niederschlag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismissSheet() })
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
        .task {
            series = try? await APIClient.shared.getRadarSeries(coordinates: tap.coordinate)
        }
    }

    private var header: some View {
        HStack {
            Text(kindName)
                .font(.headline)
            Spacer()
            if let rate {
                Text(units.rateString(rate))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenHeader)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var detailRows: some View {
        if rate != nil || tap.wetBulb != nil || tap.groundHeight != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let rate {
                    row(label: "Intensität",
                        value: String(localized: ServerColormapStops.stormCellSteps[ServerColormapStops.stormCellStep(rate)].label))
                }
                if let wetBulb = tap.wetBulb {
                    if rate != nil { Divider().padding(.leading, 16) }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Feuchttemperatur am Boden")
                            Spacer()
                            Text(units.preciseTemperatureString(wetBulb))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        Text("Zeigt, wie kalt die Luft wird, wenn Niederschlag in ihr verdunstet, und damit, ob Schnee bis zum Boden kommt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
                if let groundHeight = tap.groundHeight {
                    if rate != nil || tap.wetBulb != nil { Divider().padding(.leading, 16) }
                    row(label: "Geländehöhe", value: units.heightString(groundHeight))
                }
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var changeRow: some View {
        if let change {
            Text(change)
                .font(.subheadline)
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

    private var rate: Double? {
        series?.rate(at: tap.date).flatMap { $0 > 0 ? $0 : nil }
    }

    private var kindName: LocalizedStringKey {
        switch series?.kind(at: tap.date) {
        case "snow": "Schnee"
        case "sleet": "Schneeregen"
        case "rain": "Regen"
        default: "Niederschlag"
        }
    }

    private var spokenHeader: Text {
        guard let rate else { return Text(kindName) }
        let number = units.precipitationNumber(rate)
        let spokenRate = units.precipitation == .inch
            ? Text("\(number) Zoll pro Stunde")
            : Text("\(number) Millimeter pro Stunde")
        return Text("\(Text(kindName)), \(spokenRate)")
    }

    private var change: LocalizedStringKey? {
        guard let point = series?.nextKindChange(after: tap.date) else { return nil }
        let time = SettingService.formattedTime(point.timestamp)
        switch point.kind {
        case "snow": return "Ab \(time) voraussichtlich Schnee."
        case "sleet": return "Ab \(time) voraussichtlich Schneeregen."
        case "rain": return "Ab \(time) voraussichtlich Regen."
        default: return nil
        }
    }

    private var units: Units { SettingService.shared.units }
}
