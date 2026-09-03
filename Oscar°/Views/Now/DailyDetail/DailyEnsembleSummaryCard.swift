import SwiftUI

struct DailyEnsembleStat {
  let label: LocalizedStringKey
  var subtitle: LocalizedStringKey? = nil
  let value: String
  let valueColor: Color
  var date: String? = nil
}

/// "Nächsten Tage" card: the stat rows of one ensemble variable, divided.
struct DailyEnsembleSummaryCard: View {
  let stats: [DailyEnsembleStat]

  var body: some View {
    DetailCard {
      Text("Nächsten Tage")
        .font(.headline)
        .foregroundStyle(.primary)

      ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
        if index > 0 {
          Divider().overlay(.white.opacity(0.08))
        }
        LabeledContent {
          VStack(alignment: .trailing, spacing: 2) {
            Text(stat.value)
              .fontWeight(.semibold)
              .foregroundStyle(stat.valueColor)
            if let date = stat.date {
              Text(date)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(stat.label)
            if let subtitle = stat.subtitle {
              Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
}
