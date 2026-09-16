import SwiftUI

/// Runs the `shine` layer shader on a clock. Time is wrapped to a minute so it
/// stays precise as a float; the sweep period divides it evenly.
struct ShineModifier: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
            content.visualEffect { view, proxy in
                view.layerEffect(
                    ShaderLibrary.shine(.float2(proxy.size), .float(time)),
                    maxSampleOffset: .zero
                )
            }
        }
    }
}
