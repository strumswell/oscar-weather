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

    static let pearl: [Color] = [
        .white, Color(hex: 0xD6E9FF), Color(hex: 0xFFFFFF), Color(hex: 0xC9DCFF), Color(hex: 0xEDE4FF), .white
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
        case .atmosphere:
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x0A3FC2), location: 0),
                    .init(color: Color(hex: 0x1473F5), location: 0.42),
                    .init(color: Color(hex: 0x5AAEFF), location: 0.78),
                    .init(color: Color(hex: 0xB9DDFF), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if tier == .atmosphere {
            RadialGradient(colors: [Color(hex: 0xFFF6D8, alpha: 0.45), .clear], center: mirrored ? .topLeading : .topTrailing, startRadius: 0, endRadius: 220)
        } else if tier == .member {
            ZStack {
                RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Color(hex: 0x14285A, alpha: 0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 240)
            }
        }
    }

    private var kind: Float {
        switch tier {
        case .member, .atmosphere: 0
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
        ZStack {
            EllipticalGradient(
                colors: [.white.opacity(tier.isFounder ? 0.12 : 0.22), .clear],
                center: UnitPoint(x: 0.32 + tilt.width * 0.45, y: 0.22 + tilt.height * 0.45),
                endRadiusFraction: 0.75
            )
            if motion.glint >= 0 {
                let offset = -1.2 + motion.glint * 2.4
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.4),
                        .init(color: .white.opacity(0.2), location: 0.5),
                        .init(color: .clear, location: 0.6)
                    ],
                    startPoint: UnitPoint(x: offset, y: 0),
                    endPoint: UnitPoint(x: offset + 1, y: 1)
                )
            }
        }
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
        .opacity(tier.isFounder ? 0.22 : tier == .supporter || tier == .atmosphere ? 0.14 : 0.07)
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

struct MemberCardSky: View {
    let motion: MemberCardMotion
    let scale: CGFloat

    private static let puffs: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (-10, 262, 46), (52, 270, 40), (110, 266, 34), (170, 276, 38), (240, 282, 44), (320, 276, 40), (400, 268, 46)
    ]

    var body: some View {
        let tilt = motion.tilt
        ZStack {
            Canvas { context, _ in
                for puff in Self.puffs {
                    let rect = CGRect(x: (puff.x - puff.r) * scale, y: (puff.y - puff.r) * scale, width: puff.r * 2 * scale, height: puff.r * 2 * scale)
                    context.fill(Path(ellipseIn: rect), with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.75), .white.opacity(0.45), .white.opacity(0)]),
                        center: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.12),
                        startRadius: 0,
                        endRadius: rect.width / 2
                    ))
                }
            }
            .offset(x: -tilt.width * 10 * scale, y: -tilt.height * 6 * scale)
            MemberCardFlightPath()
                .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 6]))
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: tilt.width * 4 * scale, y: tilt.height * 3 * scale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MemberCardFlightPath: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 236, y: 170))
            path.addCurve(to: CGPoint(x: 300, y: 112), control1: CGPoint(x: 262, y: 168), control2: CGPoint(x: 268, y: 124))
            path.addCurve(to: CGPoint(x: 314, y: 86), control1: CGPoint(x: 336, y: 100), control2: CGPoint(x: 334, y: 70))
            path.addCurve(to: CGPoint(x: 362, y: 54), control1: CGPoint(x: 296, y: 100), control2: CGPoint(x: 330, y: 52))
        }
    }
}
