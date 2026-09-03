import SwiftUI

/// The playhead readout, styled like the retired chart cards' selection
/// tooltip: a frosted box beside the playhead, only always visible now. Each
/// series is a dot + label + value row in the lens' fixed order (primary
/// first, then by altitude/depth), so rows never trade places while the
/// lines cross. The rows double as the legend.
struct HourlyReadoutBox: View {
    let model: HourlyTimelineModel
    let layout: HourlyLensLayout

    private struct Row: Identifiable {
        let id: Int
        let color: Color
        let label: String?
        let value: String
    }

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: model.clockLabel)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 1)
                ForEach(rows) { row in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 6, height: 6)
                        if let label = row.label {
                            Text(verbatim: label)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Text(verbatim: row.value)
                            .foregroundStyle(.white)
                    }
                }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(8)
            .background(.ultraThinMaterial.opacity(0.9))
            .clipShape(.rect(cornerRadius: 8))
            .shadow(radius: 4)
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for line in layout.lines.reversed() {
            guard let value = model.sample(line.values) else { continue }
            rows.append(Row(
                id: rows.count,
                color: line.color,
                label: line.label,
                value: layout.extremeFormat(value)
            ))
        }
        // The precipitation row stays put when it is dry — a 0 keeps the box
        // from resizing mid-scrub and is an answer in itself.
        if layout.showsBars, let barsLabel = layout.barsLabel {
            let rate = model.sample(model.precipitation) ?? 0
            let isSnow = (model.sample(model.snowfall) ?? 0) > 0
            rows.append(Row(
                id: rows.count,
                color: isSnow ? .cyan : .hourlyRain,
                label: barsLabel,
                value: "\(rate.formatted(.number.precision(.fractionLength(1)))) \(model.precipitationUnit)"
            ))
        }
        for band in layout.bands {
            guard let value = model.sample(band.values) else { continue }
            rows.append(Row(
                id: rows.count,
                color: .hourlyCloud,
                label: band.label,
                value: layout.extremeFormat(value)
            ))
        }
        return rows
    }
}
