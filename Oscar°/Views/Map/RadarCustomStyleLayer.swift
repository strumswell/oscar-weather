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

/// Draws the radar quad with the map's own projection matrix each frame. Frame data
/// stays as `r8Unorm` value-grid textures (grid indices, row 0 = north); the fragment
/// shader warps both frames along the pair's motion field, bilinearly samples the
/// DATA, and colormaps after interpolation via a 256×1 palette LUT.
///
/// `@unchecked Sendable`: mutable state shared with MapLibre's render thread is guarded
/// by `stateLock`; the texture caches are main-actor-only.
final class RadarCustomStyleLayer: MLNCustomStyleLayer, @unchecked Sendable {
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct RadarVOut { float4 position [[position]]; float2 uv; };
    struct RadarParams { float4 p; };   // x: phase, y: opacity, z: flow scale (per-gap), w: sampling mode (0 hard / 1 soft / 2 categorical)

    vertex RadarVOut radar_style_vs(uint vid [[vertex_id]],
                                    constant float4* clip [[buffer(0)]],
                                    constant float2* uv   [[buffer(1)]]) {
        RadarVOut out;
        out.position = clip[vid];
        out.uv = uv[vid];
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
    // Typed grids are block-coded (rain 1…153, snow 154…204, ice/mix 205…255 —
    // keep the bounds in sync with the server's TypedRadar). Nearest sampling picks
    // the block; soft mode additionally bicubic-smooths the intensity INSIDE that
    // block (Weichzeichnen works without fabricating types at boundaries) and fades
    // echo edges like the plain soft path. Dry pixels stay transparent — outward
    // feathering would tint snow rims with low rain indices.
    static half4 typed_sample(texture2d<float> tex, texture2d<half> palette,
                              sampler dataLinear, float2 uv, bool soft) {
        constexpr sampler dataNearest(filter::nearest, address::clamp_to_edge);
        constexpr sampler lutNearest(filter::nearest, address::clamp_to_edge);
        constexpr sampler lutLinear(filter::linear, address::clamp_to_edge);
        float vN = tex.sample(dataNearest, uv).r * 255.0;
        if (vN < 0.5) return half4(0.0);
        if (!soft) {
            return palette.sample(lutNearest, float2((vN + 0.5) / 256.0, 0.5));
        }
        float lo = 1.0, hi = 153.0;
        if (vN > 204.5)      { lo = 205.0; hi = 255.0; }
        else if (vN > 153.5) { lo = 154.0; hi = 204.0; }
        float vs = sample_bspline(tex, dataLinear, uv) * 255.0;
        float v = clamp(vs, lo, hi);
        // (v+0.5)/256 hits texel centers, so linear LUT sampling never blends
        // across a block edge (v is clamped to [lo, hi]).
        half4 c = palette.sample(lutLinear, float2((v + 0.5) / 256.0, 0.5));
        float fade = clamp(vs / lo, 0.0, 1.0);
        return c * half(fade * fade);
    }

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
        bool categorical = p.p.w > 1.5;
        bool soft = !categorical && p.p.w > 0.5;
        float2 f = flow.sample(dataSampler, in.uv).rg * p.p.z;
        float2 uvA = in.uv - t * f;
        float2 uvB = in.uv + (1.0 - t) * f;
        if (categorical) {
            // Typed grids: index blending would fabricate types, so look each frame
            // up and blend the premultiplied COLORS — the motion warp still applies
            // (it only moves sampling positions).
            bool softTyped = p.p.w > 2.5;
            half4 ca = typed_sample(frameA, palette, dataSampler, uvA, softTyped);
            half4 cb = typed_sample(frameB, palette, dataSampler, uvB, softTyped);
            return mix(ca, cb, half(t)) * half(p.p.y);
        }
        float a = soft ? sample_bspline(frameA, dataSampler, uvA) : frameA.sample(dataSampler, uvA).r;
        float b = soft ? sample_bspline(frameB, dataSampler, uvB) : frameB.sample(dataSampler, uvB).r;
        float v = mix(a, b, t);                                // blend in data (dBZ) space
        float2 lut = float2(v * (255.0 / 256.0) + (0.5 / 256.0), 0.5);
        half4 c = soft ? palette.sample(lutLinear, lut) : palette.sample(lutNearest, lut);
        return c * half(p.p.y);                                // palette is premultiplied
    }
    """

    /// How the fragment shader samples data and palette (raw value = shader param).
    enum SamplingMode: Float {
        case hard = 0             // linear data, nearest palette — crisp isobands
        case soft = 1             // bicubic data, linear palette — RainViewer look
        case categorical = 2      // nearest data, color-space blend — typed grids
        case categoricalSoft = 3  // typed grids with in-block bicubic smoothing
    }

    // Written by the coordinator (main thread), read by `draw` on MapLibre's render
    // thread — every access goes through `stateLock`.
    private let stateLock = NSLock()
    nonisolated(unsafe) private var overlayBounds: OscarRadarBounds?
    nonisolated(unsafe) private var opacity: Float = 0.7
    nonisolated(unsafe) private var textureA: MTLTexture?
    nonisolated(unsafe) private var textureB: MTLTexture?
    nonisolated(unsafe) private var flowTexture: MTLTexture?
    nonisolated(unsafe) private var flowScale: Float = 0
    nonisolated(unsafe) private var phase: Float = 0
    nonisolated(unsafe) private var samplingMode: Float = SamplingMode.soft.rawValue
    nonisolated(unsafe) private var paletteTexture: MTLTexture?
    nonisolated(unsafe) private var zeroFlowTexture: MTLTexture?

    // Render state (built in didMove(to:) from the map's own Metal backend)
    nonisolated(unsafe) private var device: MTLDevice?
    nonisolated(unsafe) private var pipelineState: MTLRenderPipelineState?
    nonisolated(unsafe) private var depthStencilState: MTLDepthStencilState?

    // r8 texture cache: whole timeline on roomy devices, scrub window on tight ones.
    // Rebuild on miss is a ~16–29 MB memcpy from the frame's in-RAM grid indices.
    // Main-thread only (the render thread never touches the cache, just the two refs).
    // The byte budget is GLOBAL: radar + model layer can coexist, and independent
    // per-instance budgets would double the worst case. Enforcement evicts LRU
    // entries from whichever live instance holds the most bytes.
    private var textures: [String: MTLTexture] = [:]
    private var textureLRU: [String] = []
    private var textureBytes = 0
    @MainActor private static let sharedTextureBudget = adaptiveCacheBudget(
        fraction: 0.1, floor: 96 * 1024 * 1024, cap: 256 * 1024 * 1024)
    @MainActor private static var sharedTextureBytes = 0
    // Layers currently in a style (didMove/willMove); weak so removal can't leak.
    @MainActor private static let instances = NSHashTable<RadarCustomStyleLayer>.weakObjects()

    // Flow-field textures for the active motion payload (a few KB each; keep all).
    private var motionData: RadarMotionData?
    private var flowTextures: [Int: MTLTexture] = [:]

    // Playback (main thread): the layer owns the cross-fade/morph phase and frame
    // advancement, exactly like the old Metal overlay — the state's internal 0.5 s
    // Timer is cancelled while this runs (it would double-advance).
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
        stateLock.withLock {
            overlayBounds = bounds
            self.opacity = opacity
        }
    }

    /// Data/palette sampling: `.soft` = RainViewer look, `.hard` = crisp isobands,
    /// `.categorical` = typed grids (nearest sampling, color-space blend).
    @MainActor func setSampling(_ mode: SamplingMode) {
        let changed = stateLock.withLock { () -> Bool in
            guard samplingMode != mode.rawValue else { return false }
            samplingMode = mode.rawValue
            return true
        }
        if changed { setNeedsDisplay() }
    }

    // MARK: Lifecycle

    override func didMove(to mapView: MLNMapView) {
        // Style mutations happen on the main thread; `backendResource()` is
        // main-actor-isolated in the framework's annotations.
        MainActor.assumeIsolated {
            let resource = mapView.backendResource()
            guard let device = resource.device else {
                mapLibreLogger.error("custom layer: no Metal device from backendResource")
                return
            }

            let pipeline: MTLRenderPipelineState
            // Read EVERY format from the map's actual MTKView. A mismatch (device MSAA
            // sample count, different depth format) does NOT fail pipeline creation —
            // it silently rejects every draw call at encode time: blank layer on
            // device while the simulator happens to match.
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

            // 1×1 zero flow bound whenever a pair has no motion field — the warp
            // degrades to the plain cross-fade with no shader variant.
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
            // Purge here too (not just in the coordinator) so a removed layer can
            // never keep counting against the shared texture budget.
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
        // Premultiply so LINEAR palette sampling (soft mode) interpolates correctly
        // through transparent entries; nearest sampling is unaffected.
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

    /// Swap in a region's motion payload; flow textures rebuild lazily per field.
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

    /// The frame's `r8Unorm` texture (grid indices, natural row order), cached.
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
        Self.sharedTextureBytes += payload.width * payload.height
        Self.enforceSharedTextureBudget()
        return texture
    }

    /// Evict LRU textures from whichever live layer holds the most bytes until the
    /// GLOBAL budget is met; every instance keeps at least its most recent texture.
    @MainActor
    private static func enforceSharedTextureBudget() {
        while sharedTextureBytes > sharedTextureBudget {
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
            Self.sharedTextureBytes -= old.width * old.height
        }
    }

    /// rg16Float flow texture for a motion field, in UV DISPLACEMENT PER SERVER STEP
    /// (the shader multiplies by the pair's gap/step). Built once per field.
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

    /// Show a frame pair, morphing along `flowFieldIndex` (an index into the motion
    /// payload's fields) scaled by `flowScale` = actual-gap / step. nil / 0 (loop
    /// seam, gaps while loading, motion not fetched) fall back to the plain cross-fade.
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
        Self.sharedTextureBytes -= textureBytes
        textureBytes = 0
        flowTextures.removeAll()
        stateLock.withLock {
            textureA = nil
            textureB = nil
            flowTexture = nil
            flowScale = 0
        }
    }

    /// App-level memory-warning hook: every live layer drops its cached textures
    /// except the pair currently on screen (the visible frame must survive or the
    /// map blanks; everything else is a ~16–29 MB memcpy away on demand).
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
        Self.sharedTextureBytes += keptBytes - textureBytes
        textures = kept
        textureLRU = keptLRU
        textureBytes = keptBytes
        // Flow textures are a few KB each and rebuild lazily; the bound current
        // flowTexture ref survives in the render state.
        flowTextures.removeAll()
    }

    /// Drop the palette texture. Required on a variable switch: `hasPalette` gates the
    /// coordinator's re-apply loop, so a stale palette would otherwise stick forever
    /// (precip's plasma rendering temperature/wind grids).
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
            // Hold fully on frame B until the advance lands (display() resets phase);
            // if the next frame is still downloading this just dwells — no snap-back.
            stateLock.withLock { phase = 1 }
            if !awaitingAdvance {
                awaitingAdvance = true
                playbackAdvance?()
            }
        } else {
            let value = playbackInterpolates ? Float(t) : 0
            stateLock.withLock { phase = value }
        }
        setNeedsDisplay()
    }

    // MARK: Draw (called by MapLibre every rendered frame)

    // One-shot diagnostic: which guard blocks the first draw of this layer instance.
    private var didLogFirstDraw = false

    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        // Snapshot the drawable state — `draw` runs on MapLibre's render thread.
        // `self.` is load-bearing: the guard below re-declares these names as
        // locals typed from `snapshot`, and unqualified lookup on the release
        // Swift compiler binds the closure to those locals → "circular reference"
        // (the beta compiler resolves to the properties and builds fine).
        let snapshot = stateLock.withLock {
            (pipeline: self.pipelineState, depthStencil: self.depthStencilState,
             texA: self.textureA, texB: self.textureB, palette: self.paletteTexture,
             flow: self.flowTexture ?? self.zeroFlowTexture, flowScale: self.flowScale,
             bounds: self.overlayBounds, phase: self.phase, opacity: self.opacity,
             sampling: self.samplingMode)
        }
        let shouldLogFirstDraw = stateLock.withLock {
            guard !didLogFirstDraw else { return false }
            didLogFirstDraw = true
            return true
        }
        if shouldLogFirstDraw {
            // One-shot per display(): only worth a log line when a guard would block.
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
              let bounds = snapshot.bounds else { return }
        let textureB = snapshot.texB

        // Corners → Web-Mercator [0,1] → tile coordinates (× worldSize) → clip space.
        // The matrix multiply happens on the CPU in DOUBLE precision: tile coordinates
        // reach ~2^zoom·512 and float32 vertices would jitter at deep zoom.
        let worldSize = 512.0 * pow(2.0, context.zoomLevel)
        func mercator(_ latitude: Double, _ longitude: Double) -> (x: Double, y: Double) {
            (WebMercator.unitX(longitude: longitude) * worldSize,
             WebMercator.unitY(latitude: latitude) * worldSize)
        }
        let m = context.projectionMatrix
        func clip(_ p: (x: Double, y: Double)) -> SIMD4<Float> {
            // Column-major MLNMatrix4, position (x, y, 1, 1) as in the official example.
            let x = m.m00 * p.x + m.m10 * p.y + m.m20 + m.m30
            let y = m.m01 * p.x + m.m11 * p.y + m.m21 + m.m31
            let z = m.m02 * p.x + m.m12 * p.y + m.m22 + m.m32
            let w = m.m03 * p.x + m.m13 * p.y + m.m23 + m.m33
            return SIMD4(Float(x), Float(y), Float(z), Float(w))
        }

        // Triangle-strip order NW, NE, SW, SE; texture row 0 = north.
        let clipPositions: [SIMD4<Float>] = [
            clip(mercator(bounds.north, bounds.west)),
            clip(mercator(bounds.north, bounds.east)),
            clip(mercator(bounds.south, bounds.west)),
            clip(mercator(bounds.south, bounds.east)),
        ]
        let uvs: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1),
        ]
        var params = SIMD4<Float>(snapshot.phase, snapshot.opacity, snapshot.flowScale, snapshot.sampling)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBytes(clipPositions, length: MemoryLayout<SIMD4<Float>>.stride * 4, index: 0)
        renderEncoder.setVertexBytes(uvs, length: MemoryLayout<SIMD2<Float>>.stride * 4, index: 1)
        renderEncoder.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        renderEncoder.setFragmentTexture(textureA, index: 0)
        renderEncoder.setFragmentTexture(textureB ?? textureA, index: 1)
        renderEncoder.setFragmentTexture(paletteTexture, index: 2)
        renderEncoder.setFragmentTexture(flowTexture, index: 3)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

/// Breaks the CADisplayLink retain cycle (the link retains its target).
private final class RadarPlaybackLinkProxy: NSObject {
    weak var target: RadarCustomStyleLayer?
    @MainActor @objc func tick(_ link: CADisplayLink) { target?.playbackTick(link) }
}
