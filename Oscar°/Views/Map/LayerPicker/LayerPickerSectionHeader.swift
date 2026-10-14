import SwiftUI

struct LayerPickerSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    var infoSymbol: String?
    var infoHint: LocalizedStringKey = "Öffnet die Erklärung zu Wettermodellen"
    var onInfoTap: (() -> Void)?

    var body: some View {
        HStack {
            if let onInfoTap {
                Button(action: onInfoTap) {
                    titleLabel
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(infoHint))
            } else {
                titleLabel
            }
            Spacer()
            if let detail {
                detailLabel(detail)
            }
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let infoSymbol {
                Image(systemName: infoSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private func detailLabel(_ detail: LocalizedStringKey) -> some View {
        Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct LayerPickerGroupHeader: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    var showsLiveDot = false
    var onInfoTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let onInfoTap {
                Button(action: onInfoTap) {
                    titleRow
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Öffnet die Erklärung zu Wettermodellen"))
            } else {
                titleRow
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.weight(.bold))
            if onInfoTap != nil {
                Image(systemName: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if showsLiveDot {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
    }
}
