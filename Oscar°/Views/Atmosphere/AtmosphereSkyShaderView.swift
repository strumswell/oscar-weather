import SwiftUI

struct AtmosphereSkyShaderView: View {
    let snapshot: AtmosphereSnapshot
    let size: CGSize
    var moonGlow: Float = 0
    var pacing: SimulationPacing = .active

    var body: some View {
        if snapshot.thunderIntensity > 0.05 {
            TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 20.0), paused: pacing.isPaused)) { timeline in
                sky(time: shaderTime(timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            sky(time: 0)
        }
    }

    private func sky(time: Float) -> some View {
        Rectangle().fill(skyShader(time: time))
    }

    private func shaderTime(_ seconds: Double) -> Float {
        Float(seconds.truncatingRemainder(dividingBy: 4096))
    }

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
