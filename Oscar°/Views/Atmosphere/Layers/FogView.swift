import SwiftUI

struct FogView: View {
    let density: Double
    let nightAmount: Double
    var pacing: SimulationPacing = .active

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let shade = 0.85 - 0.5 * nightAmount
            TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 20.0), paused: pacing.isPaused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    LinearGradient(
                        colors: [.clear, Color(white: shade).opacity(0.30 * density)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    ForEach(0..<3, id: \.self) { band in
                        let phase = Double(band) * 2.1
                        let period = 38.0 + Double(band) * 11.0
                        let sway = sin(t * 2 * .pi / period + phase)

                        Ellipse()
                            .fill(Color(white: shade))
                            .frame(
                                width: width * 1.7,
                                height: height * (0.13 + 0.03 * Double(band))
                            )
                            .blur(radius: 30)
                            .opacity((0.16 + 0.07 * Double(band)) * density)
                            .position(
                                x: width * (0.5 + 0.22 * sway),
                                y: height * (0.58 + 0.14 * Double(band))
                            )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
