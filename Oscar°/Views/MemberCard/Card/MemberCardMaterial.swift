import SwiftUI

enum MemberCardPalette {
    static let holo: [Color] = [
        Color(hex: 0xFF8FBF), Color(hex: 0xFFD56B), Color(hex: 0x9DFFB0),
        Color(hex: 0x7FD8FF), Color(hex: 0xB69BFF), Color(hex: 0xFF8FBF)
    ]
    static let warm: [Color] = [
        Color(hex: 0xFFF3DC), Color(hex: 0xFFD08A), .white, Color(hex: 0xF7B064), Color(hex: 0xFFE9C2)
    ]
    static let sunset: [Color] = [
        Color(hex: 0xF8C56E), Color(hex: 0xFFE9C2), Color(hex: 0xF49A5A), Color(hex: 0xFFD08A), Color(hex: 0xD2566A)
    ]

    static let aspect: CGFloat = 1.7

    static func cornerRadius(for width: CGFloat) -> CGFloat {
        22 * width / 428
    }
}

struct MemberCardMaterial: View {
    let tier: MemberTier
    var mirrored = false

    var body: some View {
        base
            .colorEffect(ShaderLibrary.memberCardMaterial(.float(kind), .float(amount)))
            .overlay { highlight }
    }

    @ViewBuilder
    private var base: some View {
        switch tier {
        case .member:
            LinearGradient(
                colors: [Color(hex: 0x3D70BF), Color(hex: 0x6C9DDD), Color(hex: 0xA8CAF0)],
                startPoint: mirrored ? .bottomTrailing : .topLeading,
                endPoint: mirrored ? .topLeading : .bottomTrailing
            )
        case .supporter:
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x2A1846), location: 0),
                    .init(color: Color(hex: 0x7A2E64), location: 0.3),
                    .init(color: Color(hex: 0xD2566A), location: 0.58),
                    .init(color: Color(hex: 0xF49A5A), location: 0.84),
                    .init(color: Color(hex: 0xF8C56E), location: 1)
                ],
                startPoint: mirrored ? .bottomTrailing : .topLeading,
                endPoint: mirrored ? .topLeading : .bottomTrailing
            )
        case .founder, .founderSupporter:
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0x272A32), location: 0),
                    .init(color: Color(hex: 0x0E0F12), location: 0.58),
                    .init(color: Color(hex: 0x060708), location: 1)
                ],
                center: mirrored ? .topTrailing : .topLeading,
                startRadius: 0,
                endRadius: 520
            )
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if tier == .member {
            ZStack {
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Color(hex: 0x14285A, alpha: 0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 240)
            }
        }
    }

    private var kind: Float {
        switch tier {
        case .member: 0
        case .supporter: 1
        case .founder, .founderSupporter: 2
        }
    }

    private var amount: Float {
        tier.isFounder ? 0.05 : 0.06
    }
}

struct MemberCardGlare: View {
    let motion: MemberCardMotion
    let tier: MemberTier

    var body: some View {
        let tilt = motion.tilt
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [.white.opacity(tier.isFounder ? 0.16 : 0.32), .clear],
                    center: UnitPoint(x: 0.32 + tilt.width * 0.45, y: 0.22 + tilt.height * 0.45),
                    startRadius: 0,
                    endRadius: proxy.size.width * 0.55
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.38),
                        .init(color: .white.opacity(0.1), location: 0.47),
                        .init(color: .clear, location: 0.56)
                    ],
                    startPoint: UnitPoint(x: tilt.width * 0.3, y: 0),
                    endPoint: UnitPoint(x: 1 + tilt.width * 0.3, y: 1)
                )
                if motion.glint >= 0 {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.24), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.22, height: proxy.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .position(x: proxy.size.width * (-0.25 + motion.glint * 1.5), y: proxy.size.height / 2)
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

struct MemberCardSheen: View {
    let motion: MemberCardMotion
    let tier: MemberTier

    var body: some View {
        let shift = motion.tilt.width * 0.5 + motion.tilt.height * 0.2
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.22),
                .init(color: Color(hex: 0xFF78BE, alpha: 0.55), location: 0.34),
                .init(color: Color(hex: 0xFFD66B, alpha: 0.55), location: 0.42),
                .init(color: Color(hex: 0x8CFFBE, alpha: 0.55), location: 0.5),
                .init(color: Color(hex: 0x78D2FF, alpha: 0.55), location: 0.58),
                .init(color: Color(hex: 0xB496FF, alpha: 0.55), location: 0.66),
                .init(color: .clear, location: 0.78)
            ],
            startPoint: UnitPoint(x: -0.4 + shift, y: -0.2),
            endPoint: UnitPoint(x: 1.0 + shift, y: 1.2)
        )
        .blendMode(.screen)
        .opacity(tier.isFounder ? 0.22 : tier == .supporter ? 0.14 : 0.07)
        .allowsHitTesting(false)
    }
}

struct MemberCardFoil: View {
    let colors: [Color]
    let motion: MemberCardMotion

    var body: some View {
        let shift = motion.tilt.width * 0.6 + motion.tilt.height * 0.25
        LinearGradient(
            colors: colors,
            startPoint: UnitPoint(x: -0.7 + shift, y: 0.2),
            endPoint: UnitPoint(x: 1.1 + shift, y: 0.8)
        )
    }
}

struct MemberCardHoloCat: View {
    let motion: MemberCardMotion

    var body: some View {
        MemberCardFoil(colors: MemberCardPalette.holo, motion: motion)
            .mask {
                Image("logo-oscar-cat")
                    .resizable()
                    .scaledToFit()
            }
            .accessibilityHidden(true)
    }
}
