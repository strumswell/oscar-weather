import SwiftUI

struct MemberCardFace: View {
    let tier: MemberTier
    let title: String?
    let since: Date
    let stamps: [MemberCardStampSpec]
    let hiddenStampID: String?
    let slamTrigger: Int
    let width: CGFloat
    let motion: MemberCardMotion

    var body: some View {
        let s = width / 428
        ZStack(alignment: .topLeading) {
            MemberCardMaterial(tier: tier)
            if tier == .atmosphere {
                MemberCardSky(motion: motion, scale: s)
            }
            MemberCardSheen(motion: motion, tier: tier)
            wordmark(s)
                .padding(.leading, 24 * s)
                .padding(.top, 20 * s)
            nameBlock(s)
                .padding(.leading, 24 * s)
                .padding(.top, 100 * s)
            stampLayer(s)
            sinceLine(s)
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 24 * s)
                .padding(.bottom, 20 * s)
            badge(s)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, 22 * s)
                .padding(.top, 20 * s)
            MemberCardGlare(motion: motion, tier: tier)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: width / MemberCardPalette.aspect)
        .clipShape(.rect(cornerRadius: MemberCardPalette.cornerRadius(for: width)))
        .overlay {
            RoundedRectangle(cornerRadius: MemberCardPalette.cornerRadius(for: width))
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func wordmark(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text(verbatim: "Oscar°")
                .font(.system(size: 22 * s, weight: .heavy, design: .rounded))
            Text(verbatim: "CLUB")
                .font(.system(size: 9 * s, weight: .bold))
                .fontWidth(.expanded)
                .tracking(2.6 * s)
                .opacity(0.75)
        }
    }

    private func nameBlock(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            name(s)
            if let title {
                Text(verbatim: MemberTitle.displayName(for: title))
                    .font(.system(size: 16 * s, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 270 * s, alignment: .leading)
                    .opacity(0.88)
            }
        }
    }

    @ViewBuilder
    private func name(_ s: CGFloat) -> some View {
        let text = Text(verbatim: tier.name)
            .font(.system(size: 32 * s, weight: .black))
            .fontWidth(.expanded)
            .tracking(-0.6 * s)
        if tier.isFounder {
            text.foregroundStyle(.clear).overlay {
                MemberCardFoil(colors: MemberCardPalette.holo, motion: motion).mask { text }
            }
        } else if tier == .supporter {
            text.foregroundStyle(.clear).overlay {
                MemberCardFoil(colors: MemberCardPalette.warm, motion: motion).mask { text }
            }
        } else if tier == .atmosphere {
            text.foregroundStyle(.clear).overlay {
                MemberCardFoil(colors: MemberCardPalette.pearl, motion: motion).mask { text }
            }
        } else {
            text
        }
    }

    private func sinceLine(_ s: CGFloat) -> some View {
        Text(verbatim: Self.sinceText(tier: tier, since: since, format: .dateTime.month(.twoDigits).year(.twoDigits)))
            .textCase(.uppercase)
            .font(.system(size: 12 * s, weight: .semibold, design: .monospaced))
            .tracking(2.4 * s)
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.45), radius: 0, y: 1)
            .shadow(color: .white.opacity(0.3), radius: 0, y: -1)
    }

    private static func sinceText(tier: MemberTier, since: Date, format: Date.FormatStyle) -> String {
        tier.isFounder ? String(localized: "Seit der Beta") : String(localized: "Mitglied seit \(since.formatted(format))")
    }

    @ViewBuilder
    private func badge(_ s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 14 * s) {
            if tier == .founderSupporter {
                Text(verbatim: "SUPPORTER")
                    .font(.system(size: 10 * s, weight: .heavy))
                    .tracking(1.6 * s)
                    .foregroundStyle(Color(hex: 0x2A1846))
                    .padding(.horizontal, 10 * s)
                    .padding(.vertical, 5 * s)
                    .background {
                        MemberCardFoil(colors: MemberCardPalette.sunset, motion: motion)
                            .clipShape(.capsule)
                    }
                    .overlay {
                        Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                    }
                    .padding(.top, 10 * s)
            }
            if tier.isFounder {
                MemberCardHoloCat(motion: motion)
                    .frame(width: 46 * s, height: 42 * s)
            } else {
                Image("logo-oscar-cat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40 * s, height: 36 * s)
                    .opacity(0.5)
                    .accessibilityHidden(true)
            }
        }
    }

    private func stampLayer(_ s: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            ForEach(stamps) { spec in
                stamp(spec, s)
                    .opacity(spec.id == hiddenStampID ? 0 : 1)
                    .padding(.trailing, spec.trailing * s)
                    .padding(.bottom, spec.bottomInset * s)
            }
        }
    }

    @ViewBuilder
    private func stamp(_ spec: MemberCardStampSpec, _ s: CGFloat) -> some View {
        if spec.id == stamps.last?.id {
            MemberCardSlammingStamp(spec: spec, diameter: 96 * s, trigger: slamTrigger)
        } else {
            MemberCardStamp(spec: spec, diameter: 96 * s)
                .rotationEffect(.degrees(spec.rotation))
        }
    }

    private var accessibilityText: Text {
        Text(verbatim: Self.summary(tier: tier, title: title, since: since, stamps: stamps))
    }

    static func summary(status: MemberStatus) -> String {
        summary(tier: status.style, title: status.title, since: status.since, stamps: status.stamps)
    }

    static func summary(tier: MemberTier, title: String?, since: Date, stamps: [MemberCardStampSpec]) -> String {
        var parts = ["Oscar° Club", tier.styleName]
        if let title { parts.append(MemberTitle.displayName(for: title)) }
        parts.append(sinceText(tier: tier, since: since, format: .dateTime.month(.wide).year()))
        parts += stamps.map { [$0.top, $0.big, $0.bottom].filter { !$0.isEmpty }.joined(separator: " ") }
        return parts.joined(separator: ", ")
    }
}
