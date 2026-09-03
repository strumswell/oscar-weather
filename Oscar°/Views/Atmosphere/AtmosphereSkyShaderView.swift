import SwiftUI

// Internal (not private): the onboarding scene dioramas reuse the same sky —
// including its lightning-flash timeline — with hand-built snapshots.
struct AtmosphereSkyShaderView: View {
    let snapshot: AtmosphereSnapshot
    let size: CGSize
    var moonGlow: Float = 0
    var pacing: SimulationPacing = .active

    var body: some View {
        // Lightning flashes need a live clock; any other sky is a static
        // frame that only changes with the snapshot.
        if snapshot.thunderIntensity > 0.05 {
            TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 20.0), paused: pacing.isPaused)) { timeline in
                sky(time: shaderTime(timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            sky(time: shaderTime(snapshot.timestamp))
        }
    }

    private func sky(time: Float) -> some View {
        Rectangle().fill(skyShader(time: time))
    }

    /// Wraps the clock so it survives the trip into Float precision.
    private func shaderTime(_ seconds: Double) -> Float {
        Float(seconds.truncatingRemainder(dividingBy: 4096))
    }

    /// Mirrors SunView.sunX so the shader's glow lobe tracks the drawn sun.
    private var sunX: Float {
        (snapshot.timeOfDay - 0.3) * 1.8
    }

    private func skyShader(time: Float) -> Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "atmosphereSky"),
            arguments: [
                .float2(Float(size.width), Float(size.height)),
                .float(time),
                .float(snapshot.sunElevation),
                .float(snapshot.cloudDensity),
                .float(snapshot.precipitationIntensity),
                .float(snapshot.snowfallIntensity),
                .float(snapshot.thunderIntensity),
                .float(snapshot.haze),
                .float(snapshot.turbidity),
                .float(sunX),
                .float(moonGlow)
            ]
        )
    }
}
