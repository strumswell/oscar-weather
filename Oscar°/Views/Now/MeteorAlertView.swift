import SwiftUI

struct MeteorAlertView: View {
    let event: MeteorShowerEvent

    @Environment(NowPresentationCoordinator.self) private var presentation

    var body: some View {
        Button(action: openDetails) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text(MeteorShowerCopy.bannerText(for: event.presentation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cyan.opacity(0.3), in: Capsule())
            .cardBackground(in: Capsule())
            .cardBorder(Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("now.meteor")
        .accessibilityLabel(Text(MeteorShowerCopy.bannerText(for: event.presentation)))
        .accessibilityHint(
            Text(String(
                localized: "meteor.accessibility.hint",
                defaultValue: "Öffnet Details zum Sternschnuppenschauer"
            ))
        )
    }

    private func openDetails() {
        UIApplication.shared.playHapticFeedback()
        presentation.present(.meteorShower(event))
    }
}

#Preview {
    let event = MeteorShowerEvent(
        id: "PER",
        name: "Perseids",
        status: "peak",
        presentation: "many_tonight",
        zhr: 100,
        visibility: MeteorShowerVisibility(
            classification: "excellent",
            observable: true,
            radiantRises: true,
            radiantVisible: true,
            maxRadiantAltitude: 55.5,
            bestTime: nil
        ),
        source: "IMO"
    )
    MeteorAlertView(event: event)
        .environment(NowPresentationCoordinator())
        .padding()
}
