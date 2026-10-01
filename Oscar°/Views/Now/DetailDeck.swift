import SwiftUI

/// Eyebrow and title over the sim, above a detail deck.
struct DetailDeckCaption: View {
    let eyebrow: String
    let title: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: eyebrow)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .contentTransition(.numericText())
                .animation(.snappy, value: eyebrow)

            Text(verbatim: title)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2.5, y: 1)

            if let footnote {
                Text(verbatim: footnote)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One row of a detail deck: its live value in the header, its chart
/// unfolding in place underneath while expanded.
struct DetailDeckRow<Chart: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let value: String
    let isExpanded: Bool
    let showsDivider: Bool
    let toggle: () -> Void
    @ViewBuilder let chart: Chart

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
            }

            VStack(spacing: 0) {
                Button(action: toggle) {
                    header
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    chart
                        .frame(height: 176)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isExpanded ? 0.09 : 0))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(isExpanded ? 0.5 : 0.4))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: value))
        .accessibilityHint(isExpanded ? Text("Klappt das Diagramm ein") : Text("Zeigt das Diagramm"))
    }
}

extension View {
    func detailDeckCard() -> some View {
        padding(6)
            .cardBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .cardBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
