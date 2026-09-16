import SwiftUI

struct MeteorShowerNotice: View {
    let event: MeteorShowerEvent
    let phase: MeteorShowerPhase
    let date: Date
    let timeZone: TimeZone

    @Environment(NowPresentationCoordinator.self) private var presentation

    private var time: String {
        HourlyFormatting.timeString(timestamp: date.timeIntervalSince1970, timeZone: timeZone)
    }

    var body: some View {
        Button(action: openDetails) {
            VStack {
                Text(time)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ZStack {
                    // Match the weather cards' row heights, including Dynamic Type.
                    Text("0,0 mm").font(.footnote).hidden()
                    Text(String(localized: "meteor.hourly.notice", defaultValue: "Meteore"))
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.top, 3)
                MeteorShowerEmblem(size: 35)
                ZStack {
                    Text("0°").hidden()
                    Text(MeteorShowerCopy.showerName(for: event.id))
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(width: HourlyForecastCard.cardWidth)
            .cardBackground()
            .clipShape(.rect(cornerRadius: 10))
            .cardBorder()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("now.meteor")
        .accessibilityLabel(Text("\(time), \(MeteorShowerCopy.showerName(for: event.id)), \(MeteorShowerCopy.bannerText(for: phase))"))
        .accessibilityHint(
            Text(String(
                localized: "meteor.accessibility.hint",
                defaultValue: "Öffnet Details zum Sternschnuppenschauer"
            ))
        )
    }

    private func openDetails() {
        Haptics.impact()
        presentation.present(.meteorShower(event))
    }
}

/// Shares the supplied shooting-star artwork between the hourly strip and details.
struct MeteorShowerEmblem: View {
    var size: CGFloat = 44

    var body: some View {
        Image("star_shower")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    let event = MeteorShowerEvent(id: "PER", peak: .now, condition: "good")
    MeteorShowerNotice(event: event, phase: .peakTonight, date: .now, timeZone: .current)
        .environment(NowPresentationCoordinator())
        .font(.system(size: 18))
        .padding()
}
