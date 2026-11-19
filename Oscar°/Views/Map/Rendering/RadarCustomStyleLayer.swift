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
    // snow — x/y: hourly-step blend at frame A / frame B, z: strength (0 = overlay off)
    // snowRamp — x: °C per field texel unit, y: field offset °C, z: °C per terrain texel unit,
    //            w: 1 / (rain_above − snow_below)
    // pattern — xy: flake tiles per uv unit at the coarser zoom octave, z: blend to the finer
    //           octave, w: rain_above °C
    struct RadarParams { float4 p; float4 wipe; float4 snow; float4 snowRamp; float4 pattern; };

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

    static half4 lookup(texture2d<half> palette, float v, bool soft) {
        constexpr sampler lutNearest(filter::nearest, address::clamp_to_edge);
        constexpr sampler lutLinear(filter::linear, address::clamp_to_edge);
        float2 lut = float2(v * (255.0 / 256.0) + (0.5 / 256.0), 0.5);
        return soft ? palette.sample(lutLinear, lut) : palette.sample(lutNearest, lut);
    }

    // Snowflake lattice, fixed to the map: one flake on every tile corner and centre.
    // Each flake fades in at its own mask level, so the rain–snow boundary thins out
    // flake by flake instead of dimming, and nothing pops while the mask drifts.
    static half2 flakes(texture2d<half> tile, float2 q, float2 qdx, float2 qdy, float mask) {
        constexpr sampler tileSampler(filter::linear, mip_filter::linear, address::repeat);
        float2 corner = round(q), centre = floor(q) + 0.5;
        float2 d0 = q - corner, d1 = q - centre;
        float2 cell = dot(d0, d0) < dot(d1, d1) ? corner : centre;
        float level = 0.18 + 0.64 * fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
        return tile.sample(tileSampler, q, gradient2d(qdx, qdy)).rg * half(smoothstep(level - 0.09, level + 0.09, mask));
    }

    // Two-sided backward warp (Klemen Lozar / rainymotion "Dense" / pySTEPS
    // semilagrangian): sample A along the flow at -t·f and B at +(1-t)·f. Where both
    // frames have echo, blend in DATA (dBZ-linear index) space; where only one does,
    // cross-fade the premultiplied colours so echo edges fade instead of popping.
    // flow rg = uv displacement per pair gap; a zero texture + scale 0 degrades to a
    // plain cross-fade, phase 0 to the exact frame.
    //
    // Soft mode (p.w): B-spline data sampling + LINEAR palette sampling. The palette
    // rgb is PREMULTIPLIED (setPalette), so filtering through transparent entries
    // interpolates correctly — no dark fringe at the rain edge.
    fragment half4 radar_style_fs(RadarVOut in [[stage_in]],
                                  texture2d<float> frameA [[texture(0)]],
                                  texture2d<float> frameB [[texture(1)]],
                                  texture2d<half>  palette [[texture(2)]],
                                  texture2d<float> flow    [[texture(3)]],
                                  texture2d<float> snowA   [[texture(4)]],
                                  texture2d<float> snowB   [[texture(5)]],
                                  texture2d<float> terrain [[texture(6)]],
                                  texture2d<half>  flakeTile [[texture(7)]],
                                  constant RadarParams& p [[buffer(0)]]) {
        constexpr sampler dataSampler(filter::linear, address::clamp_to_edge);
        // Derivatives must come from uniform control flow; the flake samples sit in branches.
        float2 q = in.uv * p.pattern.xy;
        float2 qdx = dfdx(q), qdy = dfdy(q);
        float t = p.p.x;
        bool soft = p.p.w > 0.5;
        float2 f = flow.sample(dataSampler, in.uv).rg * p.p.z;
        float2 uvA = in.uv - t * f;
        float2 uvB = in.uv + (1.0 - t) * f;
        float a = soft ? sample_bspline(frameA, dataSampler, uvA) : frameA.sample(dataSampler, uvA).r;
        float b = soft ? sample_bspline(frameB, dataSampler, uvB) : frameB.sample(dataSampler, uvB).r;
        half4 cA = lookup(palette, a, soft);
        half4 cB = lookup(palette, b, soft);
        half4 c = mix(mix(cA, cB, half(t)), lookup(palette, mix(a, b, t), soft), min(cA.a, cB.a));
        if (p.snow.z > 0.0 && c.a > 0.0h) {
            // Wet-bulb at the real ground: hourly sea-level field minus the terrain's share.
            // A model field, so it is not flow-warped; it only drifts with time.
            float seaLevel = mix(snowA.sample(dataSampler, in.uv).r, snowB.sample(dataSampler, in.uv).r,
                                 mix(p.snow.x, p.snow.y, t)) * p.snowRamp.x + p.snowRamp.y;
            float wetBulb = seaLevel - terrain.sample(dataSampler, in.uv).r * p.snowRamp.z;
            float mask = saturate((p.pattern.w - wetBulb) * p.snowRamp.w);
            if (mask > 0.0) {
                // Two zoom octaves cross-faded: flakes keep a steady screen size while zooming.
                half2 mark = mix(flakes(flakeTile, q, qdx, qdy, mask),
                                 flakes(flakeTile, q * 2.0, qdx * 2.0, qdy * 2.0, mask), half(p.pattern.z))
                    * c.a * half(p.snow.z);
                c.rgb = mix(c.rgb, half3(0.05h, 0.12h, 0.24h) * c.a, mark.g * 0.6h);   // dark edge
                c.rgb = mix(c.rgb, half3(c.a), mark.r);                                // white flake
            }
        }
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
    nonisolated(unsafe) private var snowTextures: (a: MTLTexture, b: MTLTexture, terrain: MTLTexture, tile: MTLTexture)?
    nonisolated(unsafe) private var snowBlend = SIMD2<Float>.zero
    nonisolated(unsafe) private var snowRamp = SIMD4<Float>.zero
    nonisolated(unsafe) private var snowRainAbove: Float = 0
    private var snowTerrain: (id: String, texture: MTLTexture)?
    /// Terrain id being inflated off the main actor, and the latest `setSnow` call waiting for it.
    private var snowInflatingID: String?
    private var snowPending: (overlay: RadarSnowOverlay, frameDate: Date, nextDate: Date?)?
    private var snowStepTextures: [String: MTLTexture] = [:]
    private var flakeTile: MTLTexture?
    /// On-screen size of one flake tile (two flakes) in points; the zoom octaves keep it within ×0.7…1.4.
    private static let flakeTilePoints = 24.0

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
    @MainActor private static var shaderLibrary: (device: MTLDevice, library: MTLLibrary)?

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
                let library: MTLLibrary
                if let cached = Self.shaderLibrary, cached.device === device {
                    library = cached.library
                } else {
                    library = try device.makeLibrary(source: Self.shaderSource, options: nil)
                    Self.shaderLibrary = (device, library)
                }
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

    /// Snow overlay for the frame pair about to be displayed; nil switches it off.
    /// Returns false only when an overlay could not be applied because Metal is not set up yet.
    @MainActor @discardableResult
    func setSnow(_ overlay: RadarSnowOverlay?, frameDate: Date?, nextDate: Date?) -> Bool {
        let device = stateLock.withLock { self.device }
        guard let overlay else {
            snowTerrain = nil
            snowStepTextures.removeAll()
            snowPending = nil
            snowInflatingID = nil
            hideSnow()
            return true
        }
        guard let frameDate, let device, !overlay.steps.isEmpty else {
            hideSnow()
            return device != nil
        }
        if snowTerrain?.id != overlay.terrainID {
            snowTerrain = nil
            snowStepTextures.removeAll()
            stateLock.withLock { snowTextures = nil }
            snowPending = (overlay, frameDate, nextDate)
            guard snowInflatingID != overlay.terrainID else { return true }
            snowInflatingID = overlay.terrainID
            let id = overlay.terrainID, data = overlay.terrainData
            Task { [weak self] in
                let payload = await RadarFrameDecodeLane.shared.decodeRawGrid(data)
                self?.terrainInflated(id: id, payload: payload)
            }
            return true
        }
        let liveKeys = Set(overlay.steps.map(\.key))
        snowStepTextures = snowStepTextures.filter { liveKeys.contains($0.key) }
        if flakeTile == nil { flakeTile = Self.makeFlakeTile(device: device) }
        guard let terrain = snowTerrain?.texture, let tile = flakeTile else { return true }
        // Steps bracketing frame A; frame B reuses the pair.
        let after = overlay.steps.firstIndex { $0.date > frameDate } ?? overlay.steps.count - 1
        let stepA = overlay.steps[max(0, after - 1)], stepB = overlay.steps[after]
        func texture(_ step: RadarSnowOverlay.Step) -> MTLTexture? {
            if let cached = snowStepTextures[step.key] { return cached }
            let made = Self.r8Texture(step.payload, device: device)
            snowStepTextures[step.key] = made
            return made
        }
        guard let a = texture(stepA), let b = texture(stepB) else { return true }
        let span = stepB.date.timeIntervalSince(stepA.date)
        func blend(_ date: Date) -> Float {
            span > 0 ? Float(min(1, max(0, date.timeIntervalSince(stepA.date) / span))) : 0
        }
        stateLock.withLock {
            snowTextures = (a, b, terrain, tile)
            snowBlend = SIMD2(blend(frameDate), blend(nextDate ?? frameDate))
            snowRamp = SIMD4(Float(overlay.fieldScale * 255), Float(overlay.fieldOffset),
                             Float(overlay.lapsePerMeter * overlay.terrainScale * 255),
                             Float(1 / (overlay.rainAbove - overlay.snowBelow)))
            snowRainAbove = Float(overlay.rainAbove)
        }
        setNeedsDisplay()
        return true
    }

    @MainActor
    private func hideSnow() {
        let wasOn = stateLock.withLock {
            let wasOn = snowTextures != nil
            snowTextures = nil
            return wasOn
        }
        if wasOn { setNeedsDisplay() }
    }

    @MainActor
    private func terrainInflated(id: String, payload: RadarGridPayload?) {
        guard snowInflatingID == id else { return }
        snowInflatingID = nil
        guard let pending = snowPending, pending.overlay.terrainID == id,
              let device = stateLock.withLock({ self.device }),
              let texture = payload.flatMap({ Self.r8Texture($0, device: device) }) else { return }
        snowPending = nil
        snowTerrain = (id, texture)
        setSnow(pending.overlay, frameDate: pending.frameDate, nextDate: pending.nextDate)
    }

    private static func r8Texture(_ payload: RadarGridPayload, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: payload.width, height: payload.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        payload.indices.withUnsafeBufferPointer { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, payload.width, payload.height),
                            mipmapLevel: 0, withBytes: buffer.baseAddress!, bytesPerRow: payload.width)
        }
        return texture
    }

    /// Flake tile, red = flake, green = the dark edge around it; one flake on the corners and
    /// one (turned) in the centre, drawn at every mip level so small flakes stay crisp.
    private static func makeFlakeTile(device: MTLDevice) -> MTLTexture? {
        let side = 128
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm, width: side, height: side, mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        for level in 0..<texture.mipmapLevelCount {
            let size = max(1, side >> level)
            func coverage(lineWidth: CGFloat) -> [UInt8] {
                var pixels = [UInt8](repeating: 0, count: size * size)
                pixels.withUnsafeMutableBytes { raw in
                    guard let context = CGContext(
                        data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
                    let unit = CGFloat(size)
                    context.setStrokeColor(gray: 1, alpha: 1)
                    context.setLineCap(.round)
                    context.setLineWidth(lineWidth * unit)
                    let radius = 0.16 * unit
                    let spots: [(CGFloat, CGFloat, CGFloat)] =
                        [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0.5, 0.5, .pi / 6)]
                    for (x, y, turn) in spots {
                        let cx = x * unit, cy = y * unit
                        for arm in 0..<6 {
                            let angle = turn + CGFloat(arm) * .pi / 3
                            let ux = cos(angle), uy = sin(angle)
                            context.move(to: CGPoint(x: cx, y: cy))
                            context.addLine(to: CGPoint(x: cx + ux * radius, y: cy + uy * radius))
                            for side in [-1.0, 1.0] {
                                let branch = angle + side * .pi / 3
                                let bx = cx + ux * radius * 0.58, by = cy + uy * radius * 0.58
                                context.move(to: CGPoint(x: bx, y: by))
                                context.addLine(to: CGPoint(x: bx + cos(branch) * radius * 0.32,
                                                            y: by + sin(branch) * radius * 0.32))
                            }
                        }
                    }
                    context.strokePath()
                }
                return pixels
            }
            let flake = coverage(lineWidth: 0.032), edge = coverage(lineWidth: 0.075)
            var texels = [UInt8](repeating: 0, count: size * size * 2)
            for i in 0..<(size * size) {
                texels[i * 2] = flake[i]
                texels[i * 2 + 1] = UInt8(max(0, Int(edge[i]) - Int(flake[i])))
            }
            texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: level,
                            withBytes: texels, bytesPerRow: size * 2)
        }
        return texture
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
        guard let device, let texture = Self.r8Texture(payload, device: device) else { return nil }
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
        snowTerrain = nil
        snowStepTextures.removeAll()
        stateLock.withLock {
            textureA = nil
            textureB = nil
            flowTexture = nil
            flowScale = 0
            snowTextures = nil
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
            if awaitingAdvance, t >= 2 {
                playbackStart += playbackInterval
                awaitingAdvance = false
            }
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
             sampling: self.samplingMode, wipe: self.wipe,
             snow: self.snowTextures, snowBlend: self.snowBlend, snowRamp: self.snowRamp,
             snowRainAbove: self.snowRainAbove)
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
        // Flake lattice in map space: tile size is fixed per power-of-two zoom level and the
        // shader cross-fades to the next level over the upper half of each octave.
        let zoom = context.zoomLevel + 0.5
        // Capped: past z14 the lattice coordinate outgrows float precision; flakes then scale with the map.
        let octave = min(14, zoom.rounded(.down))
        let fraction = zoom - octave
        let tiles = 512.0 * pow(2.0, octave) / Self.flakeTilePoints
        let spanX = WebMercator.unitX(longitude: bounds.east) - WebMercator.unitX(longitude: bounds.west)
        let spanY = WebMercator.unitY(latitude: bounds.south) - WebMercator.unitY(latitude: bounds.north)
        let octaveBlend = min(1, max(0, (fraction - 0.5) * 2))
        let params = [SIMD4<Float>(snapshot.phase, snapshot.opacity, snapshot.flowScale, snapshot.sampling),
                      snapshot.wipe,
                      SIMD4<Float>(snapshot.snowBlend.x, snapshot.snowBlend.y, snapshot.snow == nil ? 0 : 1, 0),
                      snapshot.snowRamp,
                      SIMD4<Float>(Float(spanX * tiles), Float(spanY * tiles),
                                   Float(octaveBlend * octaveBlend * (3 - 2 * octaveBlend)), snapshot.snowRainAbove)]

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBytes(clipPositions, length: MemoryLayout<SIMD4<Float>>.stride * 4, index: 0)
        renderEncoder.setVertexBytes(uvs, length: MemoryLayout<SIMD2<Float>>.stride * 4, index: 1)
        renderEncoder.setFragmentBytes(params, length: MemoryLayout<SIMD4<Float>>.stride * 5, index: 0)
        renderEncoder.setFragmentTexture(textureA, index: 0)
        renderEncoder.setFragmentTexture(textureB ?? textureA, index: 1)
        renderEncoder.setFragmentTexture(paletteTexture, index: 2)
        renderEncoder.setFragmentTexture(flowTexture, index: 3)
        // Unused slots still need a texture; the shader skips them while snow.z is 0.
        renderEncoder.setFragmentTexture(snapshot.snow?.a ?? textureA, index: 4)
        renderEncoder.setFragmentTexture(snapshot.snow?.b ?? textureA, index: 5)
        renderEncoder.setFragmentTexture(snapshot.snow?.terrain ?? textureA, index: 6)
        renderEncoder.setFragmentTexture(snapshot.snow?.tile ?? paletteTexture, index: 7)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

private final class RadarPlaybackLinkProxy: NSObject {
    weak var target: RadarCustomStyleLayer?
    @MainActor @objc func tick(_ link: CADisplayLink) { target?.playbackTick(link) }
}
