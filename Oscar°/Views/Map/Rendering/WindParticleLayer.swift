import MapLibre
import Metal
import OSLog
import QuartzCore
import UIKit
import simd

final class WindParticleLayer: MLNCustomStyleLayer, @unchecked Sendable {
    private struct Params {
        var color: SIMD4<Float>
        var viewportPixels: SIMD2<Float>
        var halfWidth: Float
        var depth: Float
        var decay: Float
        var samplePhase: Float
        var tailLength: Float
    }

    private static let pointsPerTail = WindParticleSimulation.tailLength + 1
    private static let alphaOffset =
        WindParticleSimulation.maxParticles * pointsPerTail * MemoryLayout<SIMD2<Float>>.stride
    private static let bufferLength = alphaOffset + WindParticleSimulation.maxParticles * MemoryLayout<Float>.stride

    private let stateLock = NSLock()
    nonisolated(unsafe) private weak var mapView: MLNMapView?
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var depthStencilState: MTLDepthStencilState?
    nonisolated(unsafe) private var buffers: [MTLBuffer] = []
    nonisolated(unsafe) private var bufferIndex = 0
    nonisolated(unsafe) private var field: WindField?
    nonisolated(unsafe) private var globalModelStyle = false
    nonisolated(unsafe) private var isRunning = false
    nonisolated(unsafe) private var lastDrawTime: CFTimeInterval = 0
    nonisolated(unsafe) private var simulation = WindParticleSimulation()
    nonisolated(unsafe) private var tailPoints: [SIMD2<Double>] = []
    nonisolated(unsafe) private var tailAlphas: [Float] = []
    nonisolated(unsafe) private var displayLink: CADisplayLink?

    deinit {
        displayLink?.invalidate()
    }

    @MainActor func setUsesGlobalModelStyle(_ value: Bool) {
        stateLock.withLock { globalModelStyle = value }
    }

    @MainActor func setField(_ field: WindField?) {
        stateLock.withLock {
            self.field = field
            if field?.tiles.isEmpty ?? true { simulation.reset() }
        }
    }

    @MainActor func start() {
        guard displayLink == nil else { return }
        let proxy = WindParticleLinkProxy()
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(WindParticleLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
        stateLock.withLock {
            isRunning = true
            lastDrawTime = 0
        }
    }

    @MainActor func stop() {
        displayLink?.invalidate()
        displayLink = nil
        stateLock.withLock {
            isRunning = false
            lastDrawTime = 0
            simulation.reset()
        }
        setNeedsDisplay()
    }

    @MainActor fileprivate func tick(_ link: CADisplayLink) {
        guard mapView?.window != nil else {
            link.isPaused = true
            return
        }
        setNeedsDisplay()
    }

    override func didMove(to mapView: MLNMapView) {
        MainActor.assumeIsolated {
            self.mapView = mapView
            let resource = mapView.backendResource()
            guard let device = resource.device, let mtkView = resource.mtkView,
                  let library = device.makeDefaultLibrary() else {
                weatherMapLogger.error("wind layer: no Metal device, view or default library")
                return
            }
            let depthFormat: MTLPixelFormat =
                mtkView.depthStencilPixelFormat == .invalid ? .depth32Float_stencil8
                                                            : mtkView.depthStencilPixelFormat
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "oscar-wind-particles"
            descriptor.vertexFunction = library.makeFunction(name: "wind_particle_vs")
            descriptor.fragmentFunction = library.makeFunction(name: "wind_particle_fs")
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = mtkView.colorPixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            descriptor.depthAttachmentPixelFormat = depthFormat
            descriptor.stencilAttachmentPixelFormat = depthFormat
            descriptor.rasterSampleCount = mtkView.sampleCount
            let pipeline: MTLRenderPipelineState
            do {
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                weatherMapLogger.error("wind layer: pipeline failed: \(error, privacy: .public)")
                return
            }

            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .always
            depthDescriptor.isDepthWriteEnabled = false
            let depthStencil = device.makeDepthStencilState(descriptor: depthDescriptor)
            let ring = (0..<3).compactMap { _ in
                device.makeBuffer(length: Self.bufferLength, options: .storageModeShared)
            }

            stateLock.withLock {
                pipelineState = pipeline
                depthStencilState = depthStencil
                buffers = ring
            }
        }
    }

    override func willMove(from mapView: MLNMapView) {
        MainActor.assumeIsolated {
            stop()
            self.mapView = nil
        }
        stateLock.withLock {
            pipelineState = nil
            depthStencilState = nil
            buffers = []
        }
    }

    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        let pointScale = MainActor.assumeIsolated {
            if let displayLink, displayLink.isPaused, stateLock.withLock({ isRunning }) {
                displayLink.isPaused = false
            }
            return Double(mapView.contentScaleFactor)
        }
        guard let renderEncoder,
              var frame = stateLock.withLock({ prepareFrame(context, pointScale: pointScale) }) else { return }

        let paramsLength = MemoryLayout<Params>.stride
        renderEncoder.setRenderPipelineState(frame.pipeline)
        renderEncoder.setDepthStencilState(frame.depthStencil)
        renderEncoder.setCullMode(.none)
        renderEncoder.setVertexBuffer(frame.buffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(frame.buffer, offset: Self.alphaOffset, index: 1)
        renderEncoder.setVertexBytes(&frame.params, length: paramsLength, index: 2)
        renderEncoder.setFragmentBytes(&frame.params, length: paramsLength, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0,
                                     vertexCount: 2 * Self.pointsPerTail, instanceCount: frame.count)
    }

    private func prepareFrame(_ context: MLNStyleLayerDrawingContext, pointScale: Double) -> (
        pipeline: MTLRenderPipelineState, depthStencil: MTLDepthStencilState,
        buffer: MTLBuffer, count: Int, params: Params
    )? {
        guard isRunning, let pipelineState, let depthStencilState, let field, !field.tiles.isEmpty,
              !buffers.isEmpty, context.size.width > 0, context.size.height > 0 else { return nil }
        let now = CACurrentMediaTime()
        let elapsed = lastDrawTime == 0 ? 1.0 / 60 : now - lastDrawTime
        lastDrawTime = now

        let viewport = Self.viewport(context)
        simulation.step(elapsed: elapsed, viewport: viewport, field: field,
                        usesGlobalModelStyle: globalModelStyle, thermalScale: Self.thermalScale)
        simulation.writeTails(points: &tailPoints, alphas: &tailAlphas)
        let count = min(WindParticleSimulation.maxParticles, tailAlphas.count)
        guard count > 0 else { return nil }

        let buffer = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.count
        fill(buffer, count: count, viewport: viewport)

        let depth = viewport.clip(viewport.center)
        let width = globalModelStyle ? 1.6 : 1.8
        let params = Params(
            color: globalModelStyle ? SIMD4(232 / 255, 244 / 255, 1, 0.9) : SIMD4(250 / 255, 252 / 255, 1, 0.94),
            viewportPixels: SIMD2(Float(viewport.size.x * pointScale), Float(viewport.size.y * pointScale)),
            halfWidth: Float(width * pointScale / 2 + 0.5),
            depth: Float(depth.z / depth.w),
            decay: viewport.zoomBucket <= 4 ? 0.965 : 0.95,
            samplePhase: Float(simulation.samplePhase),
            tailLength: Float(WindParticleSimulation.tailLength))
        return (pipelineState, depthStencilState, buffer, count, params)
    }

    private func fill(_ buffer: MTLBuffer, count: Int, viewport: WindParticleSimulation.Viewport) {
        let points = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: count * Self.pointsPerTail)
        let alphas = (buffer.contents() + Self.alphaOffset).bindMemory(to: Float.self, capacity: count)
        for p in 0..<count {
            let base = p * Self.pointsPerTail
            let shift = SIMD2((viewport.center.x - tailPoints[base].x).rounded(), 0)
            for j in base..<(base + Self.pointsPerTail) {
                let c = viewport.clip(tailPoints[j] + shift)
                points[j] = SIMD2(Float(c.x / c.w), Float(c.y / c.w))
            }
            alphas[p] = tailAlphas[p]
        }
    }

    private static func viewport(_ context: MLNStyleLayerDrawingContext) -> WindParticleSimulation.Viewport {
        let m = context.projectionMatrix
        let projection = simd_double4x4(columns: (
            SIMD4(m.m00, m.m01, m.m02, m.m03),
            SIMD4(m.m10, m.m11, m.m12, m.m13),
            SIMD4(m.m20, m.m21, m.m22, m.m23),
            SIMD4(m.m30, m.m31, m.m32, m.m33)))
        return WindParticleSimulation.Viewport(
            projection: projection,
            size: SIMD2(Double(context.size.width), Double(context.size.height)),
            worldPixels: 512 * pow(2, context.zoomLevel))
    }

    private static var thermalScale: Double {
        switch ProcessInfo.processInfo.thermalState {
        case .critical: 0.25
        case .serious: 0.5
        default: 1
        }
    }
}

private final class WindParticleLinkProxy: NSObject {
    weak var target: WindParticleLayer?
    @MainActor @objc func tick(_ link: CADisplayLink) { target?.tick(link) }
}
