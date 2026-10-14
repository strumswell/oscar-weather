import SwiftUI

struct MoonLitShape: Shape {
    let phase: Double
    let litOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let kappa: CGFloat = 0.5522847498

        let t = CGFloat(cos(phase * 2 * .pi))
        let side: CGFloat = litOnRight ? 1 : -1
        let limbX = side * r
        let bulge = side * t * r

        let top = CGPoint(x: c.x, y: c.y - r)
        let bottom = CGPoint(x: c.x, y: c.y + r)

        var path = Path()
        path.move(to: top)

        path.addCurve(
            to: CGPoint(x: c.x + limbX, y: c.y),
            control1: CGPoint(x: c.x + limbX * kappa, y: c.y - r),
            control2: CGPoint(x: c.x + limbX, y: c.y - r * kappa)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: c.x + limbX, y: c.y + r * kappa),
            control2: CGPoint(x: c.x + limbX * kappa, y: c.y + r)
        )

        path.addCurve(
            to: CGPoint(x: c.x + bulge, y: c.y),
            control1: CGPoint(x: c.x + bulge * kappa, y: c.y + r),
            control2: CGPoint(x: c.x + bulge, y: c.y + r * kappa)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: c.x + bulge, y: c.y - r * kappa),
            control2: CGPoint(x: c.x + bulge * kappa, y: c.y - r)
        )
        path.closeSubpath()
        return path
    }
}

struct MoonView: View {
    let phase: Double
    let altitudeProgress: Double
    let xFraction: Double
    let yFraction: Double
    let isSouthernHemisphere: Bool
    var skyDarkness: Double = 1
    var diameter: CGFloat = Self.diameter

    static let diameter: CGFloat = 68
    private static let glowTint = Color(red: 0.93, green: 0.95, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    litShape
                        .fill(Self.glowTint)
                        .blur(radius: 24 + 14 * illumination)
                        .opacity((0.50 + 0.45 * illumination) * skyDarkness)

                    litShape
                        .fill(.white)
                        .blur(radius: 6)
                        .opacity((0.60 + 0.30 * illumination) * skyDarkness)

                    Circle()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                Circle()
                    .fill(.black.opacity(0.26))

                moonPhoto
                    .opacity(0.02)

                moonPhoto
                    .brightness(0.50)
                    .contrast(1.10)
                    .saturation(0.9)
                    .mask {
                        litShape
                            .fill(.white)
                            .blur(radius: 1.6)
                            .clipShape(Circle())
                    }

                litShape
                    .fill(.white)
                    .blur(radius: 4)
                    .opacity(0.30)
                    .clipShape(Circle())
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(litOnRight ? 24 : -24))
            .opacity(0.9 + 0.15 * sin(.pi * altitudeProgress))
            .position(
                x: proxy.size.width * xFraction,
                y: proxy.size.height * yFraction
            )
        }
        .allowsHitTesting(false)
    }

    private var illumination: Double {
        MoonPhase.illumination(for: phase)
    }

    private var litOnRight: Bool {
        (phase < 0.5) != isSouthernHemisphere
    }

    private var litShape: MoonLitShape {
        MoonLitShape(phase: phase, litOnRight: litOnRight)
    }

    private var moonPhoto: some View {
        Image("moon")
            .resizable()
            .scaledToFit()
            .clipShape(Circle())
    }
}

#Preview("Phases") {
    ZStack {
        Color(red: 0.08, green: 0.09, blue: 0.18).ignoresSafeArea()
        VStack(spacing: 0) {
            ForEach([0.08, 0.25, 0.4, 0.5, 0.6, 0.75, 0.83], id: \.self) { phase in
                MoonView(
                    phase: phase,
                    altitudeProgress: 0.5,
                    xFraction: 0.5,
                    yFraction: 0.5,
                    isSouthernHemisphere: false
                )
                .frame(height: 110)
            }
        }
    }
}
