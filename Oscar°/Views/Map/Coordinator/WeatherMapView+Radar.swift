import CoreLocation
import MapLibre
import Metal
import OSLog
import Observation
import SwiftUI
import UIKit

// MARK: Radar (custom layer + motion morph + arrows)

extension WeatherMapView.Coordinator {
    func syncRadar(
        style: MLNStyle, active: Bool, state: OscarRadarState?,
        bounds: OscarRadarBounds?, frame: OscarRadarFrame?, next: OscarRadarFrame?,
        renderedIndex: Int, loadedCount: Int, frameCount: Int,
        isPlaying: Bool, motion: RadarMotionData?, smoothMotion: Bool,
        softRendering: Bool, arrowsEnabled: Bool, visible: Bool, player: (any TimelinePlayerState)?
    ) {
        guard active, let state else {
            removeArrowLayer(from: style)
            if let layer = radarLayer {
                layer.stopPlayback()
                layer.purgeTextures()
                style.removeLayer(layer)
                radarLayer = nil
                lastFrameKey = nil
                lastRenderIndex = -1
                lastBounds = nil
                radarPaletteId = nil
            }
            return
        }
        guard let bounds else { return blocked("no radar bounds (metadata not loaded)") }

        let layer: RadarCustomStyleLayer
        if let existing = radarLayer {
            layer = existing
        } else {
            layer = RadarCustomStyleLayer(identifier: WeatherMapView.radarLayerID)
            insertOverlayLayer(layer, in: style)
            radarLayer = layer
        }

        layer.configure(bounds: bounds, opacity: visible ? Float(parent.overlayOpacity) : 0)
        layer.setSampling(softRendering ? .soft : .hard)
        layer.setMotion(motion)

        let paletteId = RadarPlasma.colormapId
        if radarPaletteId != paletteId {
            radarPaletteId = paletteId
            layer.clearPalette()
            layer.purgeTextures()
            lastFrameKey = nil
            lastRenderIndex = -1
        }
        if !layer.hasPalette, !isFetchingPalette {
            isFetchingPalette = true
            Task { @MainActor [weak self, weak layer] in
                let palette = await ServerPalettes.resolve(id: paletteId) ?? RadarPlasma.buildPalette()
                if self?.radarPaletteId == paletteId {
                    layer?.setPalette(palette)
                    layer?.setNeedsDisplay()
                }
                self?.isFetchingPalette = false
            }
        }

        if lastBounds != bounds {
            // Region switch: frame keys are bare timestamps that collide across
            // regions — the texture cache must go too.
            layer.purgeTextures()
            lastBounds = bounds
            lastFrameKey = nil
            lastRenderIndex = -1
            recenterIntoRadarBoundsIfNeeded(animated: true)
        }

        let interpolate = smoothMotion && !UIAccessibility.isReduceMotionEnabled

        defer {
            syncPlayback(of: layer, state: player ?? state, playing: isPlaying && frame != nil,
                         interval: 0.5, interpolate: interpolate)
            syncArrowLayer(style: style, state: state, frame: frame, isPlaying: isPlaying,
                           enabled: arrowsEnabled)
        }

        guard let frame else {
            return blocked("no current radar frame (loaded=\(loadedCount)/\(frameCount))")
        }
        guard lastFrameKey != frame.key || lastRenderIndex != renderedIndex else { return }
        blocked(nil)

        guard let textureA = layer.texture(for: frame) else {
            // No Metal device yet (didMove pending) — retry without stamping
            // lastFrameKey, or this frame would never be re-displayed.
            scheduleSyncRetry()
            return
        }
        let textureB = next.flatMap { layer.texture(for: $0) }
        // Flow lookup: exact adjacent pair first; when the displayed pair skips
        // served frames (progressive loading), fall back to the FROM frame's
        // field and rescale by the real timestamp gap. Never morph backwards
        // across the loop seam (negative gap) or across data holes (> 1 h).
        var flowFieldIndex: Int?
        var flowScale: Float = 0
        if let motion, let next {
            let pair = motion.pairs["\(frame.key)|\(next.key)"] ?? motion.pairsByFrom[frame.key]
            if let pair,
               let gap = OscarRadarState.minutesBetween(frame.timestamp, next.timestamp),
               gap > 0, gap <= 60 {
                flowFieldIndex = pair.fieldIndex
                flowScale = Float(gap) / Float(motion.stepMinutes)
            }
        }
        layer.display(frameA: textureA, frameB: textureB,
                      flowFieldIndex: flowFieldIndex, flowScale: flowScale)
        lastFrameKey = frame.key
        lastRenderIndex = renderedIndex
    }

    /// Motion arrows for the CURRENT observed frame, built client-side from the
    /// /motion flow field + the frame's in-RAM value grid (one point feature per
    /// coarse cell that carries precipitation). Replaces the server raster
    /// vector tiles, whose stretched old-zoom tiles flashed huge arrows during
    /// zoom transitions — symbol icons are screen-space (no scaling flicker)
    /// and MapLibre's collision thins them automatically when zooming out.
    /// Hidden during playback, like the raster tiles were.
    private static let arrowSourceIdentifier = "oscar-motion-arrows"
    private static let arrowImageName = "oscar-motion-arrow"

    func syncArrowLayer(style: MLNStyle, state: OscarRadarState,
                                frame: OscarRadarFrame?, isPlaying: Bool, enabled: Bool) {
        let desiredID: String?
        if let frame, !isPlaying, enabled, let motion = state.motion,
           let pair = motion.pairsByFrom[frame.key] {
            desiredID = "\(state.region.pathComponent)-\(frame.key)-\(pair.fieldIndex)"
        } else {
            desiredID = nil
        }
        guard desiredID != arrowSourceID else { return }
        guard let desiredID, let frame, let motion = state.motion,
              let pair = motion.pairsByFrom[frame.key], let bounds = state.bounds else {
            removeArrowLayer(from: style)
            return
        }

        let features = RadarMotionArrows.arrowFeatures(
            motion: motion, fieldIndex: pair.fieldIndex,
            grid: frame.gridPayload, bounds: bounds)
        let shape = MLNShapeCollectionFeature(shapes: features)

        if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) as? MLNShapeSource {
            source.shape = shape
        } else {
            style.setImage(RadarArrowGeometry.arrowImage(), forName: Self.arrowImageName)
            let source = MLNShapeSource(identifier: Self.arrowSourceIdentifier, shape: shape)
            let layer = MLNSymbolStyleLayer(identifier: Self.arrowSourceIdentifier, source: source)
            layer.iconImageName = NSExpression(forConstantValue: Self.arrowImageName)
            layer.iconRotation = NSExpression(forKeyPath: "rotation")
            layer.iconScale = NSExpression(forKeyPath: "scale")
            // Map-aligned: arrows keep their geographic direction when the map
            // rotates; their SIZE stays screen-space at every zoom.
            layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            layer.iconAllowsOverlap = NSExpression(forConstantValue: false)
            layer.iconOpacity = NSExpression(forConstantValue: 0.9)
            style.addSource(source)
            style.addLayer(layer)     // topmost — arrows read above the labels
        }
        arrowSourceID = desiredID
    }

    private func removeArrowLayer(from style: MLNStyle) {
        guard arrowSourceID != nil else { return }
        if let layer = style.layer(withIdentifier: Self.arrowSourceIdentifier) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.arrowSourceIdentifier) { style.removeSource(source) }
        arrowSourceID = nil
    }
}

// MARK: Handover sweep (nowcast ↔ model)

extension WeatherMapView.Coordinator {
    /// When the selection crosses between the radar nowcast and the model
    /// hours, a soft light line sweeps across the map (left to right going
    /// forward, back going back) and wipes the incoming layer in behind it,
    /// each side named next to the line. Playback wrapping from the last model
    /// hour back to the radar start is a loop, not a handover: no sweep.
    func syncHandover(radarActive: Bool, showsModelPart: Bool, isPlaying: Bool) {
        defer { lastShowsModelPart = radarActive ? showsModelPart : nil }
        guard radarActive, let mapView, !UIAccessibility.isReduceMotionEnabled,
              let last = lastShowsModelPart, last != showsModelPart,
              showsModelPart || !isPlaying else { return }
        let model = parent.modelGridState?.currentLayer?.shortSourceLabel ?? ""
        handoverSweep.run(
            in: mapView, forward: showsModelPart,
            modelSide: (String(localized: "Vorhersage"), model),
            radarSide: (String(localized: "Kurzprognose"), parent.settingsService.oscarRadarRegion.sourceLabel)
        ) { [weak self] edge in
            self?.applyHandoverWipe(edge)
        }
    }

    /// Model left of the edge, radar right of it; nil ends the sweep.
    private func applyHandoverWipe(_ edge: Float?) {
        if edge == nil { syncAll() }   // hides the outgoing layer before the clip goes
        radarLayer?.setWipe(edge: edge, keepsLeft: false)
        modelLayer?.setWipe(edge: edge, keepsLeft: true)
    }
}

/// Drives one sweep on one display link: moves the light line (a gradient band
/// over the map) with a label on each side, and reports the clip edge in NDC x.
@MainActor
final class MapHandoverSweep {
    private static let duration: CFTimeInterval = 1.4
    private static let lineWidth: CGFloat = 44
    private static let labelGap: CGFloat = 14

    private let line: CAGradientLayer = {
        let line = CAGradientLayer()
        line.startPoint = CGPoint(x: 0, y: 0.5)
        line.endPoint = CGPoint(x: 1, y: 0.5)
        line.colors = [0, 0.16, 0.65, 0.16, 0].map { UIColor.white.withAlphaComponent($0).cgColor }
        line.locations = [0, 0.4, 0.5, 0.6, 1]
        line.opacity = 0
        return line
    }()
    private let modelLabel = MapHandoverSweep.makeLabel(alignment: .right)
    private let radarLabel = MapHandoverSweep.makeLabel(alignment: .left)
    private var link: CADisplayLink?
    private weak var view: UIView?
    private var start: CFTimeInterval = 0
    private var forward = true
    private var onEdge: ((Float?) -> Void)?

    var isRunning: Bool { link != nil }

    func run(in view: UIView, forward: Bool,
             modelSide: (title: String, source: String), radarSide: (title: String, source: String),
             onEdge: @escaping (Float?) -> Void) {
        self.onEdge = onEdge
        self.view = view
        self.forward = forward
        start = CACurrentMediaTime()
        if line.superlayer !== view.layer { view.layer.addSublayer(line) }
        for (label, side) in [(modelLabel, modelSide), (radarLabel, radarSide)] {
            label.attributedText = Self.text(title: side.title, source: side.source,
                                             alignment: label.textAlignment)
            label.sizeToFit()
            if label.superview !== view { view.addSubview(label) }
        }
        if link == nil {
            let proxy = HandoverLinkProxy()
            proxy.target = self
            let link = CADisplayLink(target: proxy, selector: #selector(HandoverLinkProxy.tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        step()
    }

    func stop() {
        link?.invalidate()
        link = nil
        line.opacity = 0
        modelLabel.alpha = 0
        radarLabel.alpha = 0
        let finished = onEdge
        onEdge = nil
        finished?(nil)
    }

    fileprivate func step() {
        guard let view else { return stop() }
        let t = min(1, (CACurrentMediaTime() - start) / Self.duration)
        let eased = t * t * (3 - 2 * t)
        let x = (forward ? eased : 1 - eased) * view.bounds.width
        // Quick fade in, hold, fade out over the last fifth.
        let alpha = min(1, t / 0.12, (1 - t) / 0.2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.frame = CGRect(x: x - Self.lineWidth / 2, y: 0,
                            width: Self.lineWidth, height: view.bounds.height)
        line.opacity = Float(alpha)
        CATransaction.commit()
        modelLabel.frame.origin = CGPoint(x: x - Self.labelGap - modelLabel.bounds.width,
                                          y: view.bounds.midY - modelLabel.bounds.height / 2)
        radarLabel.frame.origin = CGPoint(x: x + Self.labelGap,
                                          y: view.bounds.midY - radarLabel.bounds.height / 2)
        modelLabel.alpha = alpha
        radarLabel.alpha = alpha
        onEdge?(Float(x / max(view.bounds.width, 1) * 2 - 1))
        if t >= 1 { stop() }
    }

    private static func makeLabel(alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 2
        label.textAlignment = alignment
        label.alpha = 0
        label.isUserInteractionEnabled = false
        // Soft dark halo: legible over any radar color without a backing plate.
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.55
        label.layer.shadowRadius = 5
        label.layer.shadowOffset = .zero
        return label
    }

    /// Title over source, e.g. "Vorhersage" / "ICON-D2".
    private static func text(title: String, source: String, alignment: NSTextAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                                     weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ])
        guard !source.isEmpty else { return text }
        text.append(NSAttributedString(string: "\n" + source, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: UIColor.white.withAlphaComponent(0.75),
            .paragraphStyle: paragraph,
        ]))
        return text
    }
}

/// Breaks the CADisplayLink retain cycle (the link retains its target).
private final class HandoverLinkProxy: NSObject {
    weak var target: MapHandoverSweep?
    @MainActor @objc func tick() { target?.step() }
}
