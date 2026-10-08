import SwiftUI

/// A one-window slot reel. When `treat` changes, a strip of random stickers
/// rolls down through the window and lands on it; reels further right
/// (higher `index`) start a beat later and roll longer, so they stop in order.
/// A new `jackpot` rolls the reel onto the bought treat.
struct TreatReel: View {
    let treat: SupportTreat
    let index: Int
    let jackpot: SupportJackpot?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the window shows. Only a landing changes it, so a new `treat`
    /// never flashes up before its roll has started.
    @State private var landed: SupportTreat?
    @State private var strip: [String] = []
    @State private var offset = 0.0
    @State private var isRolling = false
    @State private var blur = 0.0
    @State private var curve = 0.0
    @State private var landings = 0
    @State private var rolls = 0

    private static let cell = 64.0
    /// The cream of an old reel strip, matching the sticker backgrounds.
    private static let paper = Color(red: 0.95, green: 0.91, blue: 0.82)

    private var shown: SupportTreat { landed ?? treat }

    var body: some View {
        VStack(spacing: 6) {
            window
            Text(shown.name)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
                .opacity(isRolling ? 0.35 : 1)
                .id(shown.id)
                .transition(.push(from: .top))
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: landings)
        .onAppear { landed = landed ?? treat }
        .onChange(of: treat) { roll(to: treat) }
        .onChange(of: jackpot) {
            if let jackpot { roll(to: jackpot.treat) }
        }
    }

    private var window: some View {
        let images = strip.isEmpty ? [shown.image] : strip
        return VStack(spacing: 0) {
            ForEach(images.enumerated(), id: \.offset) { _, image in
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .frame(width: Self.cell, height: Self.cell)
            }
        }
        .offset(y: offset)
        .frame(width: Self.cell + 16, height: Self.cell, alignment: .top)
        .modifier(ReelMotion(blur: blur, curve: curve))
        .clipped()
        .background(Self.paper)
        // The drum curving away at the top and bottom edge.
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.28), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay { payline }
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.black.opacity(0.45), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }

    /// The thin red line across the window, with a dot at each end.
    private var payline: some View {
        HStack(spacing: 0) {
            Circle().frame(width: 5, height: 5)
            Rectangle().frame(height: 1.5)
            Circle().frame(width: 5, height: 5)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 4)
        // Blinks when the reel lands.
        .keyframeAnimator(initialValue: 0.75, trigger: landings) { line, opacity in
            line.opacity(opacity)
        } keyframes: { _ in
            LinearKeyframe(0.2, duration: 0.08)
            LinearKeyframe(1, duration: 0.08)
            LinearKeyframe(0.2, duration: 0.08)
            LinearKeyframe(0.75, duration: 0.12)
        }
    }

    private func roll(to new: SupportTreat) {
        rolls += 1
        let roll = rolls
        guard !reduceMotion else {
            withAnimation(.snappy) { landed = new }
            landings += 1
            return
        }
        let spin = ReelSpin(duration: 2.2 + 0.45 * Double(index))
        // Built bottom-up: the shown sticker sits in the window, the new one at
        // the top of the strip, and the strip slides down until it arrives.
        // One spare sticker under the shown one fills the window during the kick.
        let randomImage = { SupportTreat.allImages.randomElement() ?? new.image }
        let fillers = (0..<spin.cells(perSecond: 14)).map { _ in randomImage() }
        strip = [new.image] + fillers + [shown.image, randomImage()]
        offset = -Double(strip.count - 2) * Self.cell
        withAnimation(.easeOut(duration: 0.2)) { isRolling = true }
        Task { @MainActor in
            // Lets the reset strip render before the roll starts, and staggers the reels.
            try? await Task.sleep(for: .milliseconds(30 + 60 * index))
            // A short kick upwards before the reel drops, like a real reel catching.
            withAnimation(.easeOut(duration: 0.12)) { offset -= 12 }
            try? await Task.sleep(for: .milliseconds(120))
            guard roll == rolls else { return }
            withAnimation(Animation(spin)) {
                offset = 0
            } completion: {
                // A newer roll owns the strip now.
                guard roll == rolls else { return }
                // One transaction: clearing the strip and showing the new treat
                // separately would draw the old treat for a frame in between.
                withAnimation(.snappy) {
                    strip = []
                    landed = new
                    isRolling = false
                }
                landings += 1
            }
            // Smeared and bent round the drum only while the reel moves; at
            // rest the sticker sits flat and sharp.
            withAnimation(.easeIn(duration: ReelSpin.spinUp)) {
                blur = 8
                curve = 0.9
            }
            try? await Task.sleep(for: .seconds(spin.duration - ReelSpin.brake))
            withAnimation(.easeOut(duration: 0.5)) { blur = 0 }
            withAnimation(.easeOut(duration: ReelSpin.brake)) { curve = 0 }
        }
    }
}

/// The moving strip: vertical motion blur and the bend round the drum
/// (`curve` is how far the drum turns from the window's centre to its edge,
/// in radians). Animatable so both ease in and out with the spin.
@Animatable
private struct ReelMotion: ViewModifier {
    var blur: Double
    var curve: Double

    func body(content: Content) -> some View {
        content
            .layerEffect(
                ShaderLibrary.reelBlur(.float(blur)),
                maxSampleOffset: CGSize(width: 0, height: blur),
                isEnabled: blur > 0.5
            )
            .visualEffect { [curve] view, proxy in
                view.distortionEffect(
                    ShaderLibrary.reelDrum(.float2(proxy.size), .float(curve)),
                    maxSampleOffset: CGSize(width: 0, height: proxy.size.height * 0.2),
                    isEnabled: curve > 0.05
                )
            }
    }
}

/// How a real reel moves: it spins up, runs at full speed, then brakes and
/// rocks a little past the stop before settling (an ease-out-back brake whose
/// start speed matches the cruise, so there is no visible seam).
private struct ReelSpin: CustomAnimation {
    let duration: TimeInterval

    static let spinUp = 0.25
    static let brake = 0.9
    /// Overshoot of the brake; about a sixth of a sticker at 14 stickers/s.
    static let back = 1.2

    /// How many stickers pass the window at `perSecond` cruise speed.
    func cells(perSecond: Double) -> Int {
        Int((perSecond * travelTime).rounded())
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: progress(at: time))
    }

    /// Distance in units of the cruise speed: the time it would take at full speed.
    private var travelTime: Double {
        Self.spinUp / 2 + cruise + Self.brake / (Self.back + 3)
    }

    private var cruise: Double { duration - Self.spinUp - Self.brake }

    private func progress(at time: Double) -> Double {
        let speed = 1 / travelTime
        if time < Self.spinUp {
            return speed * time * time / (2 * Self.spinUp)
        }
        if time < Self.spinUp + cruise {
            return speed * (Self.spinUp / 2 + time - Self.spinUp)
        }
        let braking = speed * Self.brake / (Self.back + 3)
        let x = (time - Self.spinUp - cruise) / Self.brake - 1
        return 1 - braking + braking * (1 + (Self.back + 1) * x * x * x + Self.back * x * x)
    }
}
