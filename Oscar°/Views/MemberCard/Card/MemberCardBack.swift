import SwiftUI

struct MemberCardBackStat: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }

    @MainActor static func all(for status: MemberStatus) -> [MemberCardBackStat] {
        let stats = UsageStatsStore.shared.combined
        let units = SettingService.shared.units
        let streak = Duration.seconds(stats.streaks().longest * 86_400)
        return [
            MemberCardBackStat(
                label: String(localized: "Mitglied seit"),
                value: status.tier.isFounder ? "Beta" : status.since.formatted(.dateTime.month(.twoDigits).year(.twoDigits))
            ),
            MemberCardBackStat(label: String(localized: "Aktive Tage"), value: stats.activeDays.formatted()),
            MemberCardBackStat(label: String(localized: "Längste Serie"), value: streak.formatted(.units(allowed: [.days], width: .narrow))),
            MemberCardBackStat(
                label: String(localized: "Kältester Moment"),
                value: stats.coldest.map { units.preciseTemperatureString($0.canonical.value) } ?? "–"
            )
        ]
    }
}

struct MemberCardBack: View {
    let tier: MemberTier
    let stats: [MemberCardBackStat]
    let signature: [[CGPoint]]
    let width: CGFloat
    let motion: MemberCardMotion
    let onSignatureTap: () -> Void

    var body: some View {
        let s = width / 428
        ZStack(alignment: .topLeading) {
            MemberCardMaterial(tier: tier, mirrored: true)
            stripe(s)
                .padding(.top, 18 * s)
            Text("Unterschrift")
                .textCase(.uppercase)
                .font(.system(size: 9 * s, weight: .bold))
                .tracking(1.2 * s)
                .opacity(0.8)
                .padding(.leading, 24 * s)
                .padding(.top, 69 * s)
            MemberCardSignatureStrip(strokes: signature)
                .frame(width: 258 * s, height: 40 * s)
                .contentShape(.rect)
                .onTapGesture(perform: onSignatureTap)
                .padding(.leading, 24 * s)
                .padding(.top, 83 * s)
            MemberCardHologram(motion: motion)
                .frame(width: 96 * s, height: 52 * s)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, 24 * s)
                .padding(.top, 77 * s)
            statsGrid(s)
                .padding(.horizontal, 24 * s)
                .padding(.top, 137 * s)
            Text("Oscar° Club · Keine Zahlungskarte · oscars.love")
                .font(.system(size: 9 * s, weight: .medium))
                .tracking(0.4 * s)
                .opacity(0.7)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 24 * s)
                .padding(.bottom, 10 * s)
            MemberCardGlare(motion: motion, tier: tier)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: width / MemberCardPalette.aspect)
        .clipShape(.rect(cornerRadius: MemberCardPalette.cornerRadius(for: width)))
        .overlay {
            RoundedRectangle(cornerRadius: MemberCardPalette.cornerRadius(for: width))
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private func stripe(_ s: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x1C1815), location: 0),
                .init(color: Color(hex: 0x2C2621), location: 0.38),
                .init(color: Color(hex: 0x171311), location: 0.7),
                .init(color: Color(hex: 0x0F0C0B), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay { MemberCardStripeGloss(motion: motion) }
        .frame(height: 44 * s)
        .accessibilityHidden(true)
    }

    private func statsGrid(_ s: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16 * s, alignment: .leading), count: 2), alignment: .leading, spacing: 8 * s) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 3 * s) {
                    Text(verbatim: stat.label)
                        .textCase(.uppercase)
                        .font(.system(size: 9.5 * s, weight: .bold))
                        .tracking(1.1 * s)
                        .opacity(0.8)
                    Text(verbatim: stat.value)
                        .font(.system(size: 19 * s, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct MemberCardStripeGloss: View {
    let motion: MemberCardMotion

    var body: some View {
        let x = 0.5 + motion.tilt.width * 0.5
        LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, x - 0.18)),
                .init(color: .white.opacity(0.1), location: x),
                .init(color: .clear, location: min(1, x + 0.18))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct MemberCardHologram: View {
    let motion: MemberCardMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xDCE0E7), location: 0),
                    .init(color: Color(hex: 0x9DA4B0), location: 0.38),
                    .init(color: Color(hex: 0xF1F3F7), location: 0.58),
                    .init(color: Color(hex: 0x8F96A2), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                MemberCardFoil(colors: MemberCardPalette.holo, motion: motion)
                    .blendMode(.multiply)
                    .opacity(0.65)
            }
            .overlay {
                MemberCardHoloCat(motion: motion)
                    .padding(8)
                    .shadow(color: .white.opacity(0.6), radius: 1)
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
