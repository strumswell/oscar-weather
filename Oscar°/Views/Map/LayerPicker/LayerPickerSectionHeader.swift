import SwiftUI

/// Section header row: semibold title, optionally followed by an info symbol —
/// with `onInfoTap` the whole title cluster becomes a button (the forecast
/// sections link to the weather-model explainer). The trailing edge carries an
/// optional secondary detail, e.g. the pulsing red "live" dot for the radar
/// section.
struct LayerPickerSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    var infoSymbol: String?
    var showsLiveDot = false
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
        HStack(spacing: 5) {
            if showsLiveDot {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            Text(detail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
