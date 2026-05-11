import SwiftUI

struct BeaufortScaleInfoCard: View {
  var body: some View {
    EnvironmentDetailCard {
      Text("Beaufort-Skala")
        .font(.headline)
        .foregroundStyle(.primary)

      ForEach(Array(BeaufortScale.entries.enumerated()), id: \.element.id) { index, entry in
        if index > 0 {
          Divider().overlay(.white.opacity(0.08))
        }

        BeaufortScaleRow(entry: entry)
      }
    }
  }
}

private struct BeaufortScaleRow: View {
  let entry: BeaufortScale.Entry

  var body: some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: 2) {
        Text("\(entry.force) Bft")
          .fontWeight(.semibold)
          .foregroundStyle(valueColor)
          .monospacedDigit()

        Text(entry.range)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.name)
        Text(entry.landMeaning)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var valueColor: Color {
    entry.force == 0 ? .primary : Color(hex: entry.colorHex)
  }
}
