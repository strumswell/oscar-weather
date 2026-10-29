import SwiftUI

struct MemberCardStampSpec: Identifiable, Equatable {
    enum Shape: Equatable { case round, scallop, double, rect }

    let id: String
    let shape: Shape
    let top: String
    let big: String
    let bottom: String
    let ring: String
    let rotation: Double
    let trailing: CGFloat
    let bottomInset: CGFloat
    let seed: Float

    static func specs(tier: MemberTier, years: Int, seed: Double) -> [MemberCardStampSpec] {
        var specs: [MemberCardStampSpec] = []
        let jitter = (seed.truncatingRemainder(dividingBy: 1) - 0.5) * 8
        if tier.isFounder {
            specs.append(MemberCardStampSpec(
                id: "founder", shape: .rect,
                top: caps(String(localized: "Vorabversion")), big: caps(String(localized: "Vor 1.0")), bottom: "TESTFLIGHT", ring: "",
                rotation: -9 + jitter * 0.5, trailing: 18, bottomInset: 16, seed: 3
            ))
        }
        if years > 0 {
            let word = caps(String(localized: "Jahr \(spelledOut(years))"))
            specs.append(MemberCardStampSpec(
                id: "years",
                shape: years >= 10 ? .double : years >= 5 ? .scallop : .round,
                top: "",
                big: String(years),
                bottom: caps(years == 1 ? String(localized: "Jahr") : String(localized: "Jahre")),
                ring: "OSCAR° CLUB · \(word) · OSCAR° CLUB · \(word) · ",
                rotation: (tier.isFounder ? 14 : -10) + jitter,
                trailing: tier.isFounder ? 112 : 18,
                bottomInset: tier.isFounder ? 18 : 12,
                seed: Float(6 + years)
            ))
        }
        return specs
    }

    static func caps(_ text: String) -> String {
        text.uppercased(with: .current)
    }

    private static func spelledOut(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: number as NSNumber) ?? String(number)
    }
}

extension MemberStatus {
    var stamps: [MemberCardStampSpec] {
        MemberCardStampSpec.specs(tier: style, years: years, seed: since.timeIntervalSince1970 / 997)
    }
}

enum MemberCardStampSlam {
    static let impact = 0.42

    struct Frame {
        var scale = 1.0
        var lift = 0.0
        var spin = 0.0
        var opacity = 1.0
        var shadow = 0.0
        var bleed = 0.0
    }
}

struct MemberCardStamp: View {
    let spec: MemberCardStampSpec
    let diameter: CGFloat
    var ink: Color = .white

    var body: some View {
        let u = diameter / 96
        ZStack {
            if spec.shape == .rect {
                rectStamp(u)
            } else {
                roundStamp(u)
            }
        }
        .foregroundStyle(ink)
        .frame(width: diameter, height: diameter)
        .opacity(0.96)
        .compositingGroup()
        .layerEffect(
            ShaderLibrary.memberCardInk(.float(spec.seed), .float(Float(u))),
            maxSampleOffset: CGSize(width: 3 * u, height: 3 * u)
        )
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: [spec.top, spec.big, spec.bottom].filter { !$0.isEmpty }.joined(separator: " ")))
    }

    private func roundStamp(_ u: CGFloat) -> some View {
        let letters = Array(spec.ring)
        let step = 360 / Double(max(letters.count, 1))
        return ZStack {
            if spec.shape == .scallop {
                MemberCardScallop()
                    .stroke(lineWidth: 2 * u)
                    .padding(1.6 * u)
            } else {
                Circle()
                    .inset(by: 3 * u)
                    .stroke(lineWidth: 2.6 * u)
            }
            Circle()
                .inset(by: (spec.shape == .scallop ? 8 : 6.5) * u)
                .stroke(lineWidth: 0.9 * u)
            Circle()
                .inset(by: 22 * u)
                .stroke(lineWidth: (spec.shape == .double ? 1.8 : 1.3) * u)
            if spec.shape == .double {
                Circle()
                    .inset(by: 25 * u)
                    .stroke(lineWidth: 0.8 * u)
            }
            Canvas { context, size in
                context.translateBy(x: size.width / 2, y: size.height / 2)
                for letter in letters {
                    context.draw(
                        Text(verbatim: String(letter)).font(.system(size: 7.8 * u, weight: .heavy)).foregroundStyle(ink),
                        at: CGPoint(x: 0, y: -34.5 * u)
                    )
                    context.rotate(by: .degrees(step))
                }
            }
            VStack(spacing: 1 * u) {
                Text(verbatim: spec.big)
                    .font(.system(size: (spec.big.count > 1 ? 22 : 27) * u, weight: .black))
                    .tracking(-0.4 * u)
                Text(verbatim: spec.bottom)
                    .font(.system(size: 7.2 * u, weight: .heavy))
                    .tracking(1.3 * u)
            }
        }
    }

    private func rectStamp(_ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 7 * u)
            .stroke(lineWidth: 2.6 * u)
            .overlay {
                RoundedRectangle(cornerRadius: 4 * u)
                    .stroke(lineWidth: 1 * u)
                    .padding(4 * u)
            }
            .overlay {
                VStack(spacing: 2 * u) {
                    Text(verbatim: spec.top)
                        .font(.system(size: 7.6 * u, weight: .heavy))
                        .tracking(1 * u)
                    Text(verbatim: spec.big)
                        .font(.system(size: 13 * u, weight: .black))
                    Text(verbatim: spec.bottom)
                        .font(.system(size: 7.6 * u, weight: .heavy))
                        .tracking(1 * u)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .frame(width: 94 * u, height: 58 * u)
    }
}

struct MemberCardScallop: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.93
        var path = Path()
        for index in 0..<48 {
            let angle = Double(index) / 48 * .pi * 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct MemberCardSlammingStamp: View {
    let spec: MemberCardStampSpec
    let diameter: CGFloat
    let trigger: Int
    var ink: Color = .white

    var body: some View {
        MemberCardStamp(spec: spec, diameter: diameter, ink: ink)
            .keyframeAnimator(initialValue: MemberCardStampSlam.Frame(), trigger: trigger) { stamp, frame in
                stamp
                    .scaleEffect(frame.scale)
                    .rotationEffect(.degrees(spec.rotation + frame.spin))
                    .offset(y: -frame.lift * diameter * 0.35)
                    .opacity(frame.opacity)
                    .background {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .blur(radius: diameter * 0.12)
                            .scaleEffect(1 + frame.lift * 0.8)
                            .opacity(frame.shadow)
                    }
                    .overlay {
                        Circle()
                            .stroke(ink.opacity(0.7), lineWidth: 2)
                            .scaleEffect(0.6 + frame.bleed)
                            .opacity(frame.bleed > 0 && frame.bleed < 1 ? (1 - frame.bleed) * 0.6 : 0)
                    }
            } keyframes: { _ in
                let fall = MemberCardStampSlam.impact - 0.2
                KeyframeTrack(\.scale) {
                    MoveKeyframe(2.3)
                    LinearKeyframe(2.3, duration: 0.2)
                    CubicKeyframe(0.86, duration: fall)
                    SpringKeyframe(1, duration: 0.45, spring: .bouncy(duration: 0.4, extraBounce: 0.1))
                }
                KeyframeTrack(\.lift) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 0.2)
                    CubicKeyframe(0, duration: fall)
                }
                KeyframeTrack(\.spin) {
                    MoveKeyframe(-16)
                    LinearKeyframe(-16, duration: 0.2)
                    CubicKeyframe(0, duration: fall)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: 0.12)
                    LinearKeyframe(1, duration: fall + 0.05)
                }
                KeyframeTrack(\.shadow) {
                    MoveKeyframe(0)
                    LinearKeyframe(0.05, duration: 0.2)
                    CubicKeyframe(0.6, duration: fall)
                    LinearKeyframe(0, duration: 0.08)
                }
                KeyframeTrack(\.bleed) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: MemberCardStampSlam.impact)
                    CubicKeyframe(1, duration: 0.5)
                }
            }
    }
}
