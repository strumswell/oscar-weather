import Foundation
import Testing
import simd
@testable import Oscar_

struct WindParticleSimulationTests {
    private let size = SIMD2<Double>(400, 800)

    private func viewport(centerX: Double, zoom: Double, bearing: Double = 0) -> WindParticleSimulation.Viewport {
        let worldPixels = 512 * pow(2, zoom)
        let angle = bearing * .pi / 180
        let rotation = simd_double2x2(columns: (SIMD2(cos(angle), sin(angle)), SIMD2(-sin(angle), cos(angle))))
        let linear = simd_double2x2(diagonal: SIMD2(2 / size.x, -2 / size.y)) * rotation
        let translation = -(linear * (SIMD2(centerX, 0.33) * worldPixels))
        let projection = simd_double4x4(columns: (
            SIMD4(lowHalf: linear.columns.0, highHalf: .zero),
            SIMD4(lowHalf: linear.columns.1, highHalf: .zero),
            SIMD4(0, 0, 0, 0),
            SIMD4(lowHalf: translation, highHalf: SIMD2(0.5, 1))))
        return WindParticleSimulation.Viewport(projection: projection, size: size, worldPixels: worldPixels)
    }

    private func uniformField(u: Double, v: Double) -> WindField {
        let bounds = Components.Schemas.RadarBounds(north: 85, south: -85, west: -180, east: 180)
        return WindField(tiles: [WindFieldTile(gridWidth: 2, gridHeight: 2, bounds: bounds,
                                               u: [u, u, u, u], v: [v, v, v, v])])
    }

    private func tails(_ simulation: WindParticleSimulation) -> [ArraySlice<SIMD2<Double>>] {
        var points: [SIMD2<Double>] = []
        var alphas: [Float] = []
        simulation.writeTails(points: &points, alphas: &alphas)
        let pointsPerTail = WindParticleSimulation.tailLength + 1
        return stride(from: 0, to: points.count, by: pointsPerTail).map { points[$0..<($0 + pointsPerTail)] }
    }

    private func heads(_ simulation: WindParticleSimulation) -> [SIMD2<Double>] {
        tails(simulation).map { $0.first! }
    }

    @Test
    func viewportRoundTripsThroughARotatedProjection() {
        let view = viewport(centerX: 0.52, zoom: 6, bearing: 37)
        #expect(simd_length(view.screenPoint(view.center) - size / 2) < 1e-6)
        for screen in [SIMD2<Double>(0, 0), SIMD2(400, 0), SIMD2(123, 456), SIMD2(400, 800)] {
            let unit = view.unitPoint(screen)
            #expect(simd_length(view.screenPoint(unit) - screen) < 1e-6)
            let clip = view.clip(unit)
            let x: Double = (clip.x / clip.w + 1) * size.x / 2
            let y: Double = (1 - clip.y / clip.w) * size.y / 2
            let fromClip = SIMD2<Double>(x, y)
            #expect(simd_length(fromClip - screen) < 1e-6)
        }
    }

    @Test
    func eastwardWindMovesParticlesEast() {
        let view = viewport(centerX: 0.52, zoom: 6)
        let field = uniformField(u: 10, v: 0)
        var simulation = WindParticleSimulation()
        simulation.step(elapsed: 0, viewport: view, field: field, usesGlobalModelStyle: false, thermalScale: 1)
        let before = heads(simulation)
        simulation.step(elapsed: 1.0 / 30, viewport: view, field: field, usesGlobalModelStyle: false, thermalScale: 1)
        let after = heads(simulation)
        #expect(before.count == after.count && !before.isEmpty)
        for (old, new) in zip(before, after) {
            #expect(new.x > old.x)
            #expect(abs(new.y - old.y) < 1e-12)
        }
    }

    @Test
    func respawnedParticlesLieInsideTheRotatedViewport() {
        let view = viewport(centerX: 0.52, zoom: 6, bearing: 30)
        var simulation = WindParticleSimulation()
        simulation.step(elapsed: 1.0 / 30, viewport: view, field: WindField(tiles: []),
                        usesGlobalModelStyle: false, thermalScale: 1)
        for head in heads(simulation) {
            let screen = view.screenPoint(head)
            #expect(screen.x >= -1e-6 && screen.x <= size.x + 1e-6)
            #expect(screen.y >= -1e-6 && screen.y <= size.y + 1e-6)
        }
    }

    @Test
    func tailsStayContinuousAcrossTheAntimeridianAndRingWrap() {
        let view = viewport(centerX: 0.9995, zoom: 8)
        let field = uniformField(u: 30, v: 0)
        var simulation = WindParticleSimulation()
        for _ in 0..<150 {
            simulation.step(elapsed: 1.0 / 30, viewport: view, field: field, usesGlobalModelStyle: false, thermalScale: 1)
        }
        let headPoints = heads(simulation)
        #expect(headPoints.allSatisfy { $0.x >= 0 && $0.x < 1 })
        #expect(headPoints.contains { $0.x < 0.5 })
        for tail in tails(simulation) {
            #expect(zip(tail, tail.dropFirst()).allSatisfy {
                simd_length($0 - $1) * view.worldPixels <= 2 * 14 + 1e-6
            })
        }
    }

    @Test
    func thermalPressureShrinksTheParticleCount() {
        let view = viewport(centerX: 0.52, zoom: 6)
        let field = uniformField(u: 10, v: 0)
        var simulation = WindParticleSimulation()
        simulation.step(elapsed: 1.0 / 30, viewport: view, field: field, usesGlobalModelStyle: false, thermalScale: 1)
        let normal = heads(simulation).count
        simulation.step(elapsed: 1.0 / 30, viewport: view, field: field, usesGlobalModelStyle: false, thermalScale: 0.25)
        #expect(heads(simulation).count < normal)
    }
}
