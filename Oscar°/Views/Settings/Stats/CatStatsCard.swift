import SwiftUI

struct CatStatsCard: View {
    let counts: [String: Int]

    var body: some View {
        StatsCard(title: "Katze") {
            HStack(alignment: .bottom, spacing: 12) {
                Image("cat_sit")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 192, height: 64)
                    .frame(width: 64, height: 64, alignment: .leading)
                    .clipped()
                    .accessibilityHidden(true)
                Text(verbatim: "Oscar")
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .padding(.bottom, 8)
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.kicks)
                    tile(.catches)
                    tile(.scratches)
                }
                GridRow {
                    tile(.pets)
                    tile(.naps)
                    tile(.fish)
                }
            }
        }
    }

    private func tile(_ stat: CatStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(counts[stat.rawValue, default: 0], format: .number)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(Self.title(stat))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private static func title(_ stat: CatStat) -> LocalizedStringKey {
        switch stat {
        case .fish: "Fische gefressen"
        case .kicks: "Bälle gekickt"
        case .catches: "Angel erwischt"
        case .scratches: "Am Kratzbaum gespielt"
        case .pets: "Gestreichelt"
        case .naps: "Nickerchen"
        }
    }
}
