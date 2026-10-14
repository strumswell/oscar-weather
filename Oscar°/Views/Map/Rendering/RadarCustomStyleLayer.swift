//
//  RadarCustomStyleLayer.swift
//  Oscar°
//
//  The radar/model value-grid layer, rendered inside MapLibre's Metal render
//  loop (MLNCustomStyleLayer). See WeatherMapView.swift for the map architecture.
//

import MapLibre
import Metal
import OSLog
import UIKit

private let mapLibreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "WeatherMap")

// MARK: - Custom style layer (radar rendered inside MapLibre's Metal render loop)

final class RadarCustomStyleLayer: MLNCustomStyleLayer, @unchecked Sendable {
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct RadarVOut { float4 position [[position]]; float2 uv; float ndcX [[center_no_perspective]]; };
    // p — x: phase, y: opacity, z: flow scale (per-gap), w: sampling mode (0 hard / 1 soft)
    // wipe — x: edge (NDC x), y: kept side (+1 left of the edge, -1 right, 0 no clip), z: feather
    struct RadarParams { float4 p; float4 wipe; };

    vertex RadarVOut radar_style_vs(uint vid [[vertex_id]],
                                    constant float4* clip [[buffer(0)]],
                                    constant float2* uv   [[buffer(1)]]) {
        RadarVOut out;
        out.position = clip[vid];
        out.uv = uv[vid];
        out.ndcX = clip[vid].x / clip[vid].w;
        return out;
    }

    // Bicubic B-spline through four bilinear taps (Sigg & Hadwiger) — an all-positive
    // smoothing kernel (no ringing) that rounds the blocky data-native pixel rims the
    // way RainViewer does. Runs in DATA space, before the palette lookup.
    static float sample_bspline(texture2d<float> tex, sampler s, float2 uv) {
        float2 size = float2(tex.get_width(), tex.get_height());
        float2 coord = uv * size - 0.5;
        float2 f = fract(coord);
        float2 base = coord - f;
        float2 f2 = f * f, f3 = f2 * f;
        float2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
        float2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
        float2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
        float2 w3 = f3 / 6.0;
        float2 g0 = w0 + w1;
        float2 g1 = w2 + w3;
        float2 p0 = (base + 0.5 + (w1 / g0 - 1.0)) / size;
        float2 p1 = (base + 0.5 + (w3 / g1 + 1.0)) / size;
        return g0.y * (g0.x * tex.sample(s, float2(p0.x, p0.y)).r
                     + g1.x * tex.sample(s, float2(p1.x, p0.y)).r)
             + g1.y * (g0.x * tex.sample(s, float2(p0.x, p1.y)).r
                     + g1.x * tex.sample(s, float2(p1.x, p1.y)).r);
    }

    // Two-sided backward warp (Klemen Lozar / rainymotion "Dense" / pySTEPS
    // semilagrangian): sample A along the flow at -t·f and B at +(1-t)·f, then blend
    // in DATA (dBZ-linear index) space and colormap the result. flow rg = uv
    // displacement per pair gap; a zero texture + scale 0 degrades to a plain
    // data-space cross-fade, phase 0 to the exact frame.
    //
    // Soft mode (p.w): B-spline data sampling + LINEAR palette sampling. The palette
    // rgb is PREMULTIPLIED (setPalette), so filtering through transparent entries
    // interpolates correctly — no dark fringe at the rain edge.
    fragment half4 radar_style_fs(RadarVOut in [[stage_in]],
                                  texture2d<float> frameA [[texture(0)]],
                                  texture2d<float> frameB [[texture(1)]],
                                  texture2d<half>  palette [[texture(2)]],
                                  texture2d<float> flow    [[texture(3)]],
                                  constant RadarParams& p [[buffer(0)]]) {
        constexpr sampler dataSampler(filter::linear, address::clamp_to_edge);
        constexpr sampler lutNearest(filter::nearest, address::clamp_to_edge);
        constexpr sampler lutLinear(filter::linear, address::clamp_to_edge);
        float t = p.p.x;
        bool soft = p.p.w > 0.5;
        float2 f = flow.sample(dataSampler, in.uv).rg * p.p.z;
        float2 uvA = in.uv - t * f;
        float2 uvB = in.uv + (1.0 - t) * f;
        float a = soft ? sample_bspline(frameA, dataSampler, uvA) : frameA.sample(dataSampler, uvA).r;
        float b = soft ? sample_bspline(frameB, dataSampler, uvB) : frameB.sample(dataSampler, uvB).r;
        float v = mix(a, b, t);                                // blend in data (dBZ) space
        float2 lut = float2(v * (255.0 / 256.0) + (0.5 / 256.0), 0.5);
        half4 c = soft ? palette.sample(lutLinear, lut) : palette.sample(lutNearest, lut);
        if (p.wipe.y != 0.0) {                                 // radar ↔ model handover sweep
            float kept = (p.wipe.x - in.ndcX) * p.wipe.y;
            c *= half(smoothstep(-p.wipe.z, p.wipe.z, kept));
        }
        return c * half(p.p.y);                                // palette is premultiplied
    }
    """

    enum SamplingMode: Float {
        case hard = 0
        case soft = 1
    }

    private let stateLock = NSLock()
    nonisolated(unsafe) private var overlayBounds: OscarRadarBounds?
    nonisolated(unsafe) private var opacity: Float = 0.7
    nonisolated(unsafe) private var textureA: MTLTexture?
    nonisolated(unsafe) private var textureB: MTLTexture?
    nonisolated(unsafe) private var flowTexture: MTLTexture?
    nonisolated(unsafe) private var flowScale: Float = 0
    nonisolated(unsafe) private var phase: Float = 0
    nonisolated(unsafe) private var samplingMode: Float = SamplingMode.soft.rawValue
    nonisolated(unsafe) private var wipe = SIMD4<Float>.zero
    nonisolated(unsafe) private var paletteTexture: MTLTexture?
    nonisolated(unsafe) private var zeroFlowTexture: MTLTexture?

    nonisolated(unsafe) private var device: MTLDevice?
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var depthStencilState: MTLDepthStencilState?

    private var textures: [String: MTLTexture] = [:]
    private var textureLRU: [String] = []
    private var textureBytes = 0
    @MainActor private static let sharedTextureBudget = adaptiveCacheBudget(
        fraction: 0.1, floor: 96 * 1024 * 1024, cap: 256 * 1024 * 1024)
    @MainActor private static var totalTextureBytes: Int {
        instances.allObjects.reduce(0) { $0 + $1.textureBytes }
    }
    @MainActor private static let instances = NSHashTable<RadarCustomStyleLayer>.weakObjects()

    private var motionData: RadarMotionData?
    private var flowTextures: [Int: MTLTexture] = [:]

    nonisolated(unsafe) private var playbackLink: CADisplayLink?
    private var playbackAdvance: (() -> Void)?
    private var playbackInterval: TimeInterval = 0.5
    private var playbackStart: CFTimeInterval = 0
    private var playbackInterpolates = true
    private var awaitingAdvance = false
    var isPlaybackActive: Bool { playbackLink != nil }

    @MainActor var hasPalette: Bool {
        stateLock.withLock { paletteTexture != nil }
    }

    @MainActor func configure(bounds: OscarRadarBounds?, opacity: Float) {
        let opacityChanged = stateLock.withLock { () -> Bool in
            overlayBounds = bounds
            let changed = self.opacity != opacity
            self.opacity = opacity
            return changed
        }
        // Showing/hiding (radar ↔ model handover) must repaint even when no new frame is displayed.
        if opacityChanged { setNeedsDisplay() }
    }

    @MainActor func setSampling(_ mode: SamplingMode) {
        let changed = stateLock.withLock { () -> Bool in
            guard samplingMode != mode.rawValue else { return false }
            samplingMode = mode.rawValue
            return true
        }
        if changed { setNeedsDisplay() }
    }

    @MainActor func setWipe(edge: Float?, keepsLeft: Bool) {
        stateLock.withLock {
            wipe = edge.map { SIMD4($0, keepsLeft ? 1 : -1, 0.03, 0) } ?? .zero
        }
        setNeedsDisplay()
    }

    // MARK: Lifecycle

    override func didMove(to mapView: MLNMapView) {
        MainActor.assumeIsolated {
            let resource = mapView.backendResource()
            guard let device = resource.device else {
                mapLibreLogger.error("custom layer: no Metal device from backendResource")
                return
            }

            let pipeline: MTLRenderPipelineState
            guard let mtkView = resource.mtkView else {
                mapLibreLogger.error("custom layer: backendResource has no MTKView")
                return
            }
            let depthFormat: MTLPixelFormat =
                mtkView.depthStencilPixelFormat == .invalid ? .depth32Float_stencil8
                                                            : mtkView.depthStencilPixelFormat
            do {
                let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.label = "oscar-radar-layer"
                descriptor.vertexFunction = library.makeFunction(name: "radar_style_vs")
                descriptor.fragmentFunction = library.makeFunction(name: "radar_style_fs")
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
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                mapLibreLogger.error("custom layer: pipeline failed: \(error, privacy: .public)")
                return
            }

            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .always
            depthDescriptor.isDepthWriteEnabled = false
            let depthStencil = device.makeDepthStencilState(descriptor: depthDescriptor)

            let zeroDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rg16Float, width: 1, height: 1, mipmapped: false)
            zeroDescriptor.usage = .shaderRead
            let zero = device.makeTexture(descriptor: zeroDescriptor)
            var zeroTexel: [Float16] = [0, 0]
            zero?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                          withBytes: &zeroTexel, bytesPerRow: 2 * MemoryLayout<Float16>.stride)

            stateLock.withLock {
                self.device = device
                self.pipelineState = pipeline
                self.depthStencilState = depthStencil
                self.zeroFlowTexture = zero
            }
            Self.instances.add(self)
            mapLibreLogger.info(
                "custom layer: pipeline ready (color=\(mtkView.colorPixelFormat.rawValue) depth=\(depthFormat.rawValue) samples=\(mtkView.sampleCount))")
        }
    }

    override func willMove(from mapView: MLNMapView) {
        MainActor.assumeIsolated {
            stopPlayback()
            purgeTextures()
            Self.instances.remove(self)
        }
        stateLock.withLock {
            pipelineState = nil
            depthStencilState = nil
            textureA = nil
            textureB = nil
            flowTexture = nil
        }
    }

    // MARK: Content (main thread; the render thread only reads via the lock)

    @MainActor
    func setPalette(_ palette: [PixelRGBA]) {
        let device = stateLock.withLock { self.device }
        guard let device, palette.count >= 256 else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 256, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        var bytes = [UInt8](repeating: 0, count: 256 * 4)
        for i in 0..<256 {
            let p = palette[i], o = i * 4
            let a = Int(p.a)
            bytes[o] = UInt8((Int(p.r) * a + 127) / 255)
            bytes[o + 1] = UInt8((Int(p.g) * a + 127) / 255)
            bytes[o + 2] = UInt8((Int(p.b) * a + 127) / 255)
            bytes[o + 3] = p.a
        }
        texture.replace(region: MTLRegionMake2D(0, 0, 256, 1), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: 256 * 4)
        stateLock.withLock { paletteTexture = texture }
    }

    @MainActor
    func setMotion(_ data: RadarMotionData?) {
        guard motionData?.id != data?.id else { return }
        motionData = data
        flowTextures.removeAll()
        stateLock.withLock {
            flowTexture = nil
            flowScale = 0
        }
    }

    @MainActor
    func texture(for frame: OscarRadarFrame) -> MTLTexture? {
        texture(key: frame.key, payload: frame.gridPayload)
    }

    @MainActor
    func texture(key: String, payload: RadarGridPayload) -> MTLTexture? {
        if let cached = textures[key] {
            if let index = textureLRU.firstIndex(of: key) {
                textureLRU.remove(at: index)
                textureLRU.append(key)
            }
            return cached
        }
        let device = stateLock.withLock { self.device }
        guard let device else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: payload.width, height: payload.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        payload.indices.withUnsafeBufferPointer { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, payload.width, payload.height),
                            mipmapLevel: 0, withBytes: buffer.baseAddress!,
                            bytesPerRow: payload.width)
        }
        textures[key] = texture
        textureLRU.append(key)
        textureBytes += payload.width * payload.height
        Self.enforceSharedTextureBudget()
        return texture
    }

    @MainActor
    private static func enforceSharedTextureBudget() {
        while totalTextureBytes > sharedTextureBudget {
            let holders = instances.allObjects.filter { $0.textureLRU.count > 1 }
            guard let biggest = holders.max(by: { $0.textureBytes < $1.textureBytes }) else { return }
            biggest.evictOldestTexture()
        }
    }

    @MainActor
    private func evictOldestTexture() {
        let evicted = textureLRU.removeFirst()
        if let old = textures.removeValue(forKey: evicted) {
            textureBytes -= old.width * old.height
        }
    }

    @MainActor
    private func flowTexture(forField index: Int) -> MTLTexture? {
        if let cached = flowTextures[index] { return cached }
        let device = stateLock.withLock { self.device }
        guard let device, let data = motionData, data.fields.indices.contains(index) else { return nil }
        let cols = data.cols, rows = data.rows
        let field = data.fields[index]
        guard field.count == cols * rows * 2 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float, width: cols, height: rows, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let invW = Float16(1 / Float(data.overviewWidth))
        let invH = Float16(1 / Float(data.overviewHeight))
        var texels = [Float16](repeating: 0, count: cols * rows * 2)
        for i in 0..<(cols * rows) {
            texels[i * 2] = Float16(field[i]) * invW
            texels[i * 2 + 1] = Float16(field[cols * rows + i]) * invH
        }
        texels.withUnsafeBufferPointer { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, cols, rows), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!,
                            bytesPerRow: cols * 2 * MemoryLayout<Float16>.stride)
        }
        flowTextures[index] = texture
        return texture
    }

    @MainActor
    func display(frameA: MTLTexture?, frameB: MTLTexture?,
                 flowFieldIndex: Int? = nil, flowScale: Float = 0) {
        var flow: MTLTexture?
        if let flowFieldIndex, flowScale > 0 {
            flow = flowTexture(forField: flowFieldIndex)
        }
        stateLock.withLock {
            textureA = frameA
            textureB = frameB
            flowTexture = flow
            self.flowScale = flow != nil ? flowScale : 0
            phase = 0
        }
        playbackStart = CACurrentMediaTime()
        awaitingAdvance = false
        stateLock.withLock { didLogFirstDraw = false }
        setNeedsDisplay()
    }

    @MainActor
    func purgeTextures() {
        textures.removeAll()
        textureLRU.removeAll()
        textureBytes = 0
        flowTextures.removeAll()
        stateLock.withLock {
            textureA = nil
            textureB = nil
            flowTexture = nil
            flowScale = 0
        }
    }

    @MainActor
    static func purgeCachedTextures() {
        for layer in instances.allObjects {
            layer.trimToDisplayedTextures()
        }
    }

    @MainActor
    private func trimToDisplayedTextures() {
        let displayed = stateLock.withLock { (textureA, textureB) }
        var kept: [String: MTLTexture] = [:]
        var keptLRU: [String] = []
        var keptBytes = 0
        for key in textureLRU {
            guard let texture = textures[key],
                  texture === displayed.0 || texture === displayed.1 else { continue }
            kept[key] = texture
            keptLRU.append(key)
            keptBytes += texture.width * texture.height
        }
        textures = kept
        textureLRU = keptLRU
        textureBytes = keptBytes
        flowTextures.removeAll()
    }

    @MainActor
    func clearPalette() {
        stateLock.withLock { paletteTexture = nil }
    }

    // MARK: Playback (display link owns phase + frame advancement)

    @MainActor
    func startPlayback(interval: TimeInterval = 0.5, interpolate: Bool,
                       advance: @escaping () -> Void) {
        playbackInterval = max(0.1, interval)
        playbackInterpolates = interpolate
        playbackAdvance = advance
        guard playbackLink == nil else { return }
        let proxy = RadarPlaybackLinkProxy()
        proxy.target = self
        let link = CADisplayLink(target: proxy, selector: #selector(RadarPlaybackLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        playbackLink = link
        playbackStart = CACurrentMediaTime()
        awaitingAdvance = false
    }

    @MainActor
    func stopPlayback() {
        playbackLink?.invalidate()
        playbackLink = nil
        playbackAdvance = nil
        awaitingAdvance = false
        stateLock.withLock { phase = 0 }
        setNeedsDisplay()
    }

    @MainActor
    fileprivate func playbackTick(_ link: CADisplayLink) {
        guard playbackLink != nil else { return }
        let t = (link.timestamp - playbackStart) / playbackInterval
        if t >= 1 {
            stateLock.withLock { phase = 1 }
            if !awaitingAdvance {
                awaitingAdvance = true
                playbackAdvance?()
            }
        } else {
            stateLock.withLock { phase = playbackInterpolates ? Float(t) : 0 }
        }
        setNeedsDisplay()
    }

    // MARK: Draw (called by MapLibre every rendered frame)

    private var didLogFirstDraw = false

    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        let snapshot = stateLock.withLock {
            (pipeline: self.pipelineState, depthStencil: self.depthStencilState,
             texA: self.textureA, texB: self.textureB, palette: self.paletteTexture,
             flow: self.flowTexture ?? self.zeroFlowTexture, flowScale: self.flowScale,
             bounds: self.overlayBounds, phase: self.phase, opacity: self.opacity,
             sampling: self.samplingMode, wipe: self.wipe)
        }
        let shouldLogFirstDraw = stateLock.withLock {
            guard !didLogFirstDraw else { return false }
            didLogFirstDraw = true
            return true
        }
        if shouldLogFirstDraw {
            if snapshot.pipeline == nil || snapshot.texA == nil || snapshot.palette == nil
                || snapshot.bounds == nil {
                mapLibreLogger.info(
                    "draw blocked [\(self.identifier, privacy: .public)]: pipeline=\(snapshot.pipeline != nil) texA=\(snapshot.texA != nil) palette=\(snapshot.palette != nil) bounds=\(snapshot.bounds != nil)")
            }
        }
        guard let renderEncoder,
              let pipelineState = snapshot.pipeline,
              let depthStencilState = snapshot.depthStencil,
              let textureA = snapshot.texA,
              let paletteTexture = snapshot.palette,
              let flowTexture = snapshot.flow,
              let bounds = snapshot.bounds,
              snapshot.opacity > 0 else { return }
        let textureB = snapshot.texB

        let worldSize = 512.0 * pow(2.0, context.zoomLevel)
        func mercator(_ latitude: Double, _ longitude: Double) -> (x: Double, y: Double) {
            (WebMercator.unitX(longitude: longitude) * worldSize,
             WebMercator.unitY(latitude: latitude) * worldSize)
        }
        let m = context.projectionMatrix
        func clip(_ p: (x: Double, y: Double)) -> SIMD4<Float> {
            let x = m.m00 * p.x + m.m10 * p.y + m.m20 + m.m30
            let y = m.m01 * p.x + m.m11 * p.y + m.m21 + m.m31
            let z = m.m02 * p.x + m.m12 * p.y + m.m22 + m.m32
            let w = m.m03 * p.x + m.m13 * p.y + m.m23 + m.m33
            return SIMD4(Float(x), Float(y), Float(z), Float(w))
        }

        let clipPositions: [SIMD4<Float>] = [
            clip(mercator(bounds.north, bounds.west)),
            clip(mercator(bounds.north, bounds.east)),
            clip(mercator(bounds.south, bounds.west)),
            clip(mercator(bounds.south, bounds.east)),
        ]
        let uvs: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        let params = [SIMD4<Float>(snapshot.phase, snapshot.opacity, snapshot.flowScale, snapshot.sampling),
                      snapshot.wipe]

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBytes(clipPositions, length: MemoryLayout<SIMD4<Float>>.stride * 4, index: 0)
        renderEncoder.setVertexBytes(uvs, length: MemoryLayout<SIMD2<Float>>.stride * 4, index: 1)
        renderEncoder.setFragmentBytes(params, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        renderEncoder.setFragmentTexture(textureA, index: 0)
        renderEncoder.setFragmentTexture(textureB ?? textureA, index: 1)
        renderEncoder.setFragmentTexture(paletteTexture, index: 2)
        renderEncoder.setFragmentTexture(flowTexture, index: 3)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

private final class RadarPlaybackLinkProxy: NSObject {
    weak var target: RadarCustomStyleLayer?
    @MainActor @objc func tick(_ link: CADisplayLink) { target?.playbackTick(link) }
}
