import SwiftUI

/// The full-screen win after a purchase: light rays turn behind the bought
/// treat, copies of it rain down, marquee bulbs chase round the edge, and a
/// solid plate names what was bought. A tap or six seconds close it.
struct SupportThanks: View {
    let treat: SupportTreat
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var start = Date.now

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSince(start)
                    Canvas { canvas, size in
                        drawRays(in: &canvas, size: size, time: time)
                        drawRain(in: &canvas, size: size, time: time)
                    }
                }
                MarqueeBulbs()
                    .padding(14)
            }
            VStack(spacing: 28) {
                Image(treat.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .keyframeAnimator(initialValue: Pop(), repeating: false) { content, pop in
                        content
                            .scaleEffect(pop.scale)
                            .rotationEffect(.degrees(pop.angle))
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1.2, duration: 0.35)
                            SpringKeyframe(0.95, duration: 0.2)
                            SpringKeyframe(1, duration: 0.25)
                        }
                        KeyframeTrack(\.angle) {
                            SpringKeyframe(8, duration: 0.3)
                            SpringKeyframe(-4, duration: 0.2)
                            SpringKeyframe(0, duration: 0.25)
                        }
                    }
                    .accessibilityHidden(true)
                // A solid plate: the text never sits on the moving rays and rain.
                VStack(spacing: 10) {
                    Text("Jackpot!")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                    Text(treat.thanks)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 340)
                .background(Color(white: 0.1), in: .rect(cornerRadius: 24))
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .contentShape(.rect)
        .onTapGesture(perform: fadeOut)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.escape, fadeOut)
        .sensoryFeedback(.success, trigger: visible) { _, isVisible in isVisible }
        .onAppear {
            start = .now
            withAnimation(.easeOut(duration: 0.3)) { visible = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(6))
            fadeOut()
        }
    }

    private func fadeOut() {
        guard visible else { return }
        withAnimation(.easeIn(duration: 0.25)) { visible = false } completion: { close() }
    }

    /// Sixteen slowly turning wedges of light behind the sticker.
    private func drawRays(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.4)
        let radius = hypot(size.width, size.height)
        let wedge = Double.pi / 16
        var rays = Path()
        for i in 0..<16 {
            let angle = Double(i) * 2 * wedge + time * 0.25
            rays.move(to: center)
            rays.addArc(center: center, radius: radius, startAngle: .radians(angle), endAngle: .radians(angle + wedge), clockwise: false)
            rays.closeSubpath()
        }
        canvas.fill(rays, with: .radialGradient(
            Gradient(colors: [.yellow.opacity(0.35), .yellow.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius * 0.6
        ))
    }

    /// Copies of the treat tumbling down the screen in an endless loop.
    private func drawRain(in canvas: inout GraphicsContext, size: CGSize, time: Double) {
        let sticker = canvas.resolve(Image(treat.image))
        let fall = size.height + 120
        for i in 0..<36 {
            let side = 26 + 26 * Self.noise(i, 1)
            let speed = 160 + 220 * Self.noise(i, 2)
            let x = size.width * Self.noise(i, 3) + 18 * sin(time * 1.5 + Double(i))
            let y = (time * speed + fall * Self.noise(i, 4)).truncatingRemainder(dividingBy: fall) - 60
            var drop = canvas
            drop.opacity = 0.85
            drop.translateBy(x: x, y: y)
            drop.rotate(by: .radians(time * (Self.noise(i, 5) - 0.5) * 4))
            drop.draw(sticker, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        }
    }

    /// A stable pseudo-random number in 0..<1 for drop `index`, per property `salt`.
    private static func noise(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index * 127 + salt * 311)) * 43_758.5453
        return value - value.rounded(.down)
    }

    private struct Pop {
        var scale = 0.2
        var angle = -15.0
    }
}

/// Bulbs round the screen edge, chasing like a slot machine's marquee.
private struct MarqueeBulbs: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 10) % 3
            Canvas { canvas, size in
                // Inset by the glow radius so no bulb is cut by the canvas edge.
                let outline = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 7, dy: 7), cornerRadius: 40)
                let count = Int((size.width + size.height) * 2 / 22)
                for i in 0..<count {
                    guard let point = outline.trimmedPath(from: 0, to: Double(i) / Double(count)).currentPoint else { continue }
                    let lit = (i + phase) % 3 == 0
                    if lit {
                        canvas.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(.yellow.opacity(0.35)))
                    }
                    canvas.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)), with: .color(lit ? .yellow : .yellow.opacity(0.25)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
