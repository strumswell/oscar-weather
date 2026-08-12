//
//  ClimateDetailView.swift
//  Oscar°
//
//  Tap-through detail for the "Klima" section. Renders the summary that the section already
//  computed (passed in via the sheet), so it appears instantly — no spinner, no refetch — the
//  same way the environment detail reads already-loaded data.
//

import SwiftUI

struct ClimateDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: ClimateSummary

    private var unit: ClimateTemperatureUnit {
        ClimateTemperatureUnit(settingValue: SettingService.resolvedTemperatureUnit)
    }

    /// On a record day the headline is already the superlative, so the rank line would just repeat it.
    private var isRecord: Bool {
        summary.warmerRank == 1 || summary.warmerRank == summary.totalYears
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(climateHeadline(summary))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                        if !isRecord {
                            Text(climateRankLine(summary))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let analog = climateAnalogLine(summary, unit) {
                            Text(analog)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        InteractiveClimateRibbon(
                            stripes: summary.allStripes,
                            sigma: summary.standardDeviation,
                            unit: unit)
                        ClimateTimeAxis(firstYear: summary.firstYear, todayYear: summary.todayYear)
                        ClimateLegend()
                            .padding(.top, 2)
                    }

                    statCard

                    Text(
                        "Jeder Streifen ist die Tageshöchsttemperatur an diesem Kalendertag eines Jahres, im Vergleich zum Normalwert (1961–1990). Tippe und ziehe über die Streifen, um einzelne Jahre abzulesen."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "Datengrundlage ist die ERA5-Reanalyse: Wettermodelle verrechnen Messungen von Stationen, Satelliten, Flugzeugen und Bojen zu einem lückenlosen, weltweiten Verlauf zurück bis 1940."
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .navigationTitle("Klima")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var statCard: some View {
        VStack(spacing: 0) {
            ClimateStatRow(
                label: "Heute",
                value: "\(summary.todayHighString(unit)) (\(summary.anomalyString(unit)))")
            Divider()
            ClimateStatRow(label: "Normal (1961–1990)", value: summary.normalString(unit))
            if let trend = summary.trendString(unit) {
                Divider()
                ClimateStatRow(label: "Trend", value: trend)
            }
            Divider()
            ClimateStatRow(label: "Üblich (P10–P90)", value: summary.typicalRangeString(unit))
            Divider()
            ClimateStatRow(
                label: "Wärmster",
                value: "\(summary.recordMaxString(unit)) · \(summary.recordMax.year)")
            Divider()
            ClimateStatRow(
                label: "Kältester",
                value: "\(summary.recordMinString(unit)) · \(summary.recordMin.year)")
            Divider()
            ClimateStatRow(
                label: summary.lastRecordIsHot ? "Letzter Wärmerekord" : "Letzter Kälterekord",
                value: summary.lastRecordString(unit))
            if summary.hotYears > 0 {
                Divider()
                ClimateStatRow(
                    label: "Hitze (\(summary.hotThresholdLabel(unit)))",
                    value: climateYearCount(summary.hotYears, of: summary.totalYears))
            }
            if summary.frostYears > 0 {
                Divider()
                ClimateStatRow(
                    label: "Frost (\(summary.frostThresholdLabel(unit)))",
                    value: climateYearCount(summary.frostYears, of: summary.totalYears))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.secondary.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct ClimateStatRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}
