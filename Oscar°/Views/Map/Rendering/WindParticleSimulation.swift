import Foundation
import simd

struct WindParticleSimulation {
    static let tailLength = 64
    static let sampleInterval = 1.0 / 30
    static let maxParticles = 900

    struct Viewport {
        let projection: simd_double4x4
        let size: SIMD2<Double>
        let worldPixels: Double
        let center: SIMD2<Double>
        let unitToScreen: simd_double2x2

        init(projection: simd_double4x4, size: SIMD2<Double>, worldPixels: Double) {
            self.projection = projection
            self.size = size
            self.worldPixels = worldPixels
            let origin = projection * SIMD4(0, 0, 1, 1)
            let toScreen = SIMD2(size.x, -size.y) / (2 * origin.w) * worldPixels
            unitToScreen = simd_double2x2(columns: (
                SIMD2(projection.columns.0.x, projection.columns.0.y) * toScreen,
                SIMD2(projection.columns.1.x, projection.columns.1.y) * toScreen))
            let originScreen = SIMD2((origin.x / origin.w + 1) * size.x, (1 - origin.y / origin.w) * size.y) / 2
            center = unitToScreen.inverse * (size / 2 - originScreen)
        }

        private var lonSpan: Double { max(0.001, size.x / worldPixels * 360) }
        var continuousZoom: Double { max(0, log2(360 / lonSpan) + 1) }
        var zoomBucket: Int { max(0, min(8, Int(log2(360 / lonSpan).rounded()) + 1)) }

        func clip(_ unit: SIMD2<Double>) -> SIMD4<Double> {
            projection * SIMD4(unit.x * worldPixels, unit.y * worldPixels, 1, 1)
        }

        func screenPoint(_ unit: SIMD2<Double>) -> SIMD2<Double> {
            var delta = unit - center
            delta.x -= delta.x.rounded()
            return unitToScreen * delta + size / 2
        }

        func unitPoint(_ screen: SIMD2<Double>) -> SIMD2<Double> {
            var unit = unitToScreen.inverse * (screen - size / 2) + center
            unit.x -= unit.x.rounded(.down)
            return unit
        }
    }

    private struct Particle {
        var position: SIMD2<Double>
        var age = 0.0
        var ttl = 0.0
        var samples = 1
    }

    private var particles: [Particle] = []
    private var history: [SIMD2<Double>] = []
    private var newestSlot = 0
    private var sampleClock = 0.0

    var samplePhase: Double { sampleClock / Self.sampleInterval }

    mutating func reset() {
        self = WindParticleSimulation()
    }

    mutating func step(elapsed: Double, viewport: Viewport, field: WindField,
                       usesGlobalModelStyle: Bool, thermalScale: Double) {
        guard viewport.size.x > 0, viewport.size.y > 0, viewport.worldPixels > 0 else { return }
        let elapsed = min(0.04, max(0, elapsed))
        let ticks = elapsed * 30

        let target = Self.particleCount(viewport: viewport, thermalScale: thermalScale)
        if particles.count > target {
            history.removeLast((particles.count - target) * Self.tailLength)
            particles.removeLast(particles.count - target)
        }
        while particles.count < target {
            history.append(contentsOf: repeatElement(.zero, count: Self.tailLength))
            particles.append(Particle(position: .zero))
            spawn(particles.count - 1, in: viewport)
        }

        let metersScale = Self.velocityScale(
            zoom: viewport.continuousZoom, usesGlobalModelStyle: usesGlobalModelStyle)
        for i in particles.indices {
            particles[i].age += elapsed
            if particles[i].age >= particles[i].ttl {
                spawn(i, in: viewport)
            } else if !advance(i, ticks: ticks, metersScale: metersScale, viewport: viewport, field: field) {
                if particles[i].samples > 1 {
                    particles[i].ttl = min(particles[i].ttl, particles[i].age + 0.25)
                } else {
                    spawn(i, in: viewport)
                }
            }
        }

        sampleClock += elapsed
        while sampleClock >= Self.sampleInterval {
            sampleClock -= Self.sampleInterval
            newestSlot = (newestSlot + 1) % Self.tailLength
            for i in particles.indices {
                history[i * Self.tailLength + newestSlot] = particles[i].position
                particles[i].samples = min(Self.tailLength, particles[i].samples + 1)
            }
        }
    }

    func writeTails(points: inout [SIMD2<Double>], alphas: inout [Float]) {
        points.removeAll(keepingCapacity: true)
        alphas.removeAll(keepingCapacity: true)
        let k = Self.tailLength
        for (i, particle) in particles.enumerated() {
            var previous = particle.position
            points.append(previous)
            for n in 1...k {
                let back = min(n, particle.samples) - 1
                var point = history[i * k + (newestSlot - back + k) % k]
                point.x += (previous.x - point.x).rounded()
                points.append(point)
                previous = point
            }
            let fadeIn = particle.age / 0.25
            let fadeOut = (particle.ttl - particle.age) / 0.25
            alphas.append(Float(max(0, min(1, fadeIn, fadeOut))))
        }
    }

    private mutating func advance(_ i: Int, ticks: Double, metersScale: Double,
                                  viewport: Viewport, field: WindField) -> Bool {
        let position = particles[i].position
        let longitude = WebMercator.longitude(fromUnitX: position.x)
        let latitude = WebMercator.latitude(fromUnitY: position.y)
        guard let wind = field.sample(latitude: latitude, longitude: longitude) else { return false }

        let distance = metersScale * 2 * ticks
        let cosLat = max(0.2, cos(latitude * .pi / 180))
        let dLat = wind.y * distance / 111_320
        let dLon = wind.x * distance / (111_320 * cosLat)
        let nextLatitude = min(WebMercator.maxLatitude, max(-WebMercator.maxLatitude, latitude + dLat))
        let next = SIMD2(WebMercator.unitX(longitude: longitude + dLon),
                         WebMercator.unitY(latitude: nextLatitude))

        var delta = (next - position) * viewport.worldPixels
        let speed = simd_length(delta)
        let minStep = 0.2 * ticks
        let maxStep = 14 * ticks
        if speed > 0 && speed < minStep {
            delta *= minStep / speed
        } else if speed > maxStep {
            delta *= maxStep / speed
        }

        var moved = position + delta / viewport.worldPixels
        moved.x -= moved.x.rounded(.down)

        let screen = viewport.screenPoint(moved)
        if screen.x < -20 || screen.y < -20 || screen.x > viewport.size.x + 20 || screen.y > viewport.size.y + 20 {
            return false
        }
        particles[i].position = moved
        return true
    }

    private mutating func spawn(_ i: Int, in viewport: Viewport) {
        let screen = SIMD2(Double.random(in: 0..<viewport.size.x), Double.random(in: 0..<viewport.size.y))
        let position = viewport.unitPoint(screen)
        particles[i] = Particle(position: position, ttl: Double.random(in: 1..<5.7))
        history[i * Self.tailLength + newestSlot] = position
    }

    private static func particleCount(viewport: Viewport, thermalScale: Double) -> Int {
        let area = viewport.size.x * viewport.size.y / 1500
        let scaled = area * densityScale(zoomBucket: viewport.zoomBucket) * thermalScale
        return min(maxParticles, max(130, Int(scaled)))
    }

    private static func densityScale(zoomBucket: Int) -> Double {
        switch zoomBucket {
        case 0...2: 1.6
        case 3...4: 1.25
        case 5...6: 1.0
        default: 0.85
        }
    }

    private static func velocityScale(zoom: Double, usesGlobalModelStyle: Bool) -> Double {
        let scaleInvariant = 65.0 * pow(2, 6 - zoom)
        let farOutBoost: Double
        switch zoom {
        case ...3.5: farOutBoost = 1.7
        case ...4.5: farOutBoost = 1.3
        default: farOutBoost = 1.0
        }
        return scaleInvariant * farOutBoost * (usesGlobalModelStyle ? 1.1 : 1.0)
    }
}
