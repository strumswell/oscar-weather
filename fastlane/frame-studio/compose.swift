// Frame Studio compositor: renders App Store screenshots (device frame on the
// brand gradient with captions) from layout.json + title.strings. Replaces
// fastlane frameit, whose single global layout can't express per-screenshot
// positioning or typography.
//
// Run from the repo root (paths in layout.json resolve against it):
//   swiftc -O -o fastlane/frame-studio/.build/compose fastlane/frame-studio/compose.swift
//   fastlane/frame-studio/.build/compose [--scene 01_now_rain] [--locale de-DE] [--out preview.png]
//
// Style cascade per key: block > locales[loc] > scenes[scene] > defaults. The
// locale level beats the scene level so tr's Georgia Bold override survives
// per-scene styling (SeriouslyNostalgic has no Turkish glyphs).

import AppKit
import Foundation

let studioDir = "fastlane/frame-studio"
let screenshotsDir = "fastlane/screenshots"

// MARK: - Arguments

var sceneFilter: String?
var localeFilter: String?
var outPath: String?
var layoutPath = "\(studioDir)/layout.json"
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--scene": sceneFilter = args.isEmpty ? nil : args.removeFirst()
    case "--locale": localeFilter = args.isEmpty ? nil : args.removeFirst()
    case "--out": outPath = args.isEmpty ? nil : args.removeFirst()
    case "--layout": layoutPath = args.isEmpty ? layoutPath : args.removeFirst()
    default:
        FileHandle.standardError.write("Unknown argument: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Layout

guard let layoutData = FileManager.default.contents(atPath: layoutPath),
      let layout = (try? JSONSerialization.jsonObject(with: layoutData)) as? [String: Any] else {
    fail("cannot read \(layoutPath) — run from the repo root")
}

let defaults = layout["defaults"] as? [String: Any] ?? [:]
let scenes = layout["scenes"] as? [String: Any] ?? [:]
let locales = layout["locales"] as? [String: Any] ?? [:]

/// Per-key style lookup. `block` carries inline styles of an extra text block.
struct Style {
    let section: String
    let scene: String
    let locale: String
    var block: [String: Any]?

    private func raw(_ key: String) -> Any? {
        if let v = block?[key] { return v }
        for level in [
            (locales[locale] as? [String: Any])?[section],
            (scenes[scene] as? [String: Any])?[section],
            defaults[section],
        ] {
            if let v = (level as? [String: Any])?[key] { return v }
        }
        return nil
    }

    func number(_ key: String, _ fallback: Double) -> CGFloat {
        CGFloat((raw(key) as? NSNumber)?.doubleValue ?? fallback)
    }

    func string(_ key: String, _ fallback: String) -> String {
        raw(key) as? String ?? fallback
    }
}

// MARK: - Resources

func color(hex: String) -> NSColor {
    var h = hex.trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    if h.count == 8 {
        return NSColor(srgbRed: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                       blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

var fontCache: [String: NSFont] = [:]
func font(path: String, size: CGFloat, weight: CGFloat = 0) -> NSFont {
    let resolved = path.hasPrefix("/") ? path : "\(screenshotsDir)/\(path)"
    let cacheKey = "\(resolved)@\(size)@\(weight)"
    if let f = fontCache[cacheKey] { return f }
    guard let provider = CGDataProvider(url: URL(fileURLWithPath: resolved) as CFURL),
          let cgFont = CGFont(provider) else {
        FileHandle.standardError.write("warning: font not found at \(resolved), using system font\n".data(using: .utf8)!)
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }
    var ct = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    if weight > 0 {
        // CSS-scale weight (100…900) on the 'wght' variation axis, matching
        // the editor's font-variation-settings. Fonts without the axis (all
        // single-style files) ignore it, so no synthetic bolding either way.
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: 0x7767_6874): NSNumber(value: Double(weight))  // 'wght'
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontVariationAttribute: variation] as CFDictionary)
        ct = CTFontCreateCopyWithAttributes(ct, size, nil, descriptor)
    }
    let f = ct as NSFont
    fontCache[cacheKey] = f
    return f
}

struct Sprite {
    let image: NSImage
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
}

var spriteCache: [String: Sprite] = [:]
func sprite(at path: String) -> Sprite? {
    if let s = spriteCache[path] { return s }
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    // Pixel dimensions, not NSImage points — frame art and screenshots carry
    // differing dpi metadata.
    let rep = image.representations.max { $0.pixelsWide < $1.pixelsWide }
    let s = Sprite(image: image,
                   pixelWidth: CGFloat(rep?.pixelsWide ?? Int(image.size.width)),
                   pixelHeight: CGFloat(rep?.pixelsHigh ?? Int(image.size.height)))
    spriteCache[path] = s
    return s
}

// MARK: - Shadows

/// Rotates the wrapped drawing clockwise around a center point (degrees, like
/// CSS rotate). The flipped CTM makes positive angles read clockwise.
func withRotation(_ degrees: CGFloat, around center: CGPoint, in cg: CGContext, draw: () -> Void) {
    guard degrees != 0 else { return draw() }
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: degrees * .pi / 180)
    cg.translateBy(x: -center.x, y: -center.y)
    draw()
    cg.restoreGState()
}

/// Draws with a CoreGraphics shadow applied to the whole group when the style
/// defines one (any of blur/offset non-zero). Positive shadowY means down.
func withShadow(_ style: Style, in cg: CGContext, draw: () -> Void) {
    let blur = style.number("shadowBlur", 0)
    let sx = style.number("shadowX", 0)
    let sy = style.number("shadowY", 0)
    guard blur > 0 || sx != 0 || sy != 0 else { return draw() }
    let shadowColor = color(hex: style.string("shadowColor", "#000000"))
        .withAlphaComponent(style.number("shadowOpacity", 0.5))
    cg.saveGState()
    // Shadow offsets live in device space, which is unflipped here — negate y.
    cg.setShadow(offset: CGSize(width: sx, height: -sy), blur: blur, color: shadowColor.cgColor)
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    draw()
    cg.endTransparencyLayer()
    cg.restoreGState()
}

func nsShadow(_ style: Style) -> NSShadow? {
    let blur = style.number("shadowBlur", 0)
    let sx = style.number("shadowX", 0)
    let sy = style.number("shadowY", 0)
    guard blur > 0 || sx != 0 || sy != 0 else { return nil }
    let shadow = NSShadow()
    shadow.shadowColor = color(hex: style.string("shadowColor", "#000000"))
        .withAlphaComponent(style.number("shadowOpacity", 0.5))
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: sx, height: -sy)
    return shadow
}

// MARK: - Text

func drawText(_ text: String, style: Style) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineHeightMultiple = style.number("lineHeight", 1.05)
    switch style.string("align", "center") {
    case "left": paragraph.alignment = .left
    case "right": paragraph.alignment = .right
    default: paragraph.alignment = .center
    }
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font(path: style.string("font", "fonts/SeriouslyNostalgicFn-Regular.otf"),
                    size: style.number("size", 110),
                    weight: style.number("fontWeight", 0)),
        .foregroundColor: color(hex: style.string("color", "#FFFFFF")),
        .paragraphStyle: paragraph,
        .kern: style.number("letterSpacing", 0),
    ]
    if let shadow = nsShadow(style) { attributes[.shadow] = shadow }
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let width = style.number("width", 1200)
    let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin])
    attributed.draw(with: CGRect(x: style.number("x", 60), y: style.number("y", 90),
                                 width: width, height: ceil(bounds.height)),
                    options: [.usesLineFragmentOrigin])
}

// MARK: - Render

let fm = FileManager.default
var localeDirs = (try? fm.contentsOfDirectory(atPath: screenshotsDir))?.filter { name in
    var isDir: ObjCBool = false
    fm.fileExists(atPath: "\(screenshotsDir)/\(name)", isDirectory: &isDir)
    return isDir.boolValue && name != "fonts"
}.sorted() ?? []
if let localeFilter { localeDirs = localeDirs.filter { $0 == localeFilter } }
if localeDirs.isEmpty { fail("no locale folders matched in \(screenshotsDir)") }

let canvas = layout["canvas"] as? [String: Any]
let canvasW = CGFloat((canvas?["width"] as? NSNumber)?.doubleValue ?? 1320)
let canvasH = CGFloat((canvas?["height"] as? NSNumber)?.doubleValue ?? 2868)
let background = layout["background"] as? [String: Any] ?? [:]
let deviceConfig = layout["device"] as? [String: Any] ?? [:]
let screenOffsetX = CGFloat((deviceConfig["screenOffsetX"] as? NSNumber)?.doubleValue ?? 75)
let screenOffsetY = CGFloat((deviceConfig["screenOffsetY"] as? NSNumber)?.doubleValue ?? 66)
let screenWidth = CGFloat((deviceConfig["screenWidth"] as? NSNumber)?.doubleValue ?? 1320)
// Display corner radius in frame pixel space. Screenshots are square; without
// this clip their corners poke past the frame's rounded screen cutout into
// the transparent corner region. The cutout is an Apple squircle; a circular
// radius of 180 is the largest that stays under the bezel along the whole
// curve (217, the tip radius, cuts visible slivers mid-arc). Editable in the
// editor's device inspector.
let screenCornerRadius = CGFloat((deviceConfig["screenCornerRadius"] as? NSNumber)?.doubleValue ?? 0)

var rendered = 0

for locale in localeDirs {
    let dir = "\(screenshotsDir)/\(locale)"
    let titles = NSDictionary(contentsOfFile: "\(dir)/title.strings") as? [String: String] ?? [:]
    // Watch captures live alongside but are delivered raw (ASC wants the bare
    // watch UI, no frames) — never composite them.
    let pngs = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter {
        $0.lowercased().hasSuffix(".png") && !$0.contains("_framed") && $0.contains("-")
            && !$0.lowercased().contains("watch")
    }.sorted()

    for png in pngs {
        let stem = String(png.dropLast(4))
        guard let dash = stem.firstIndex(of: "-") else { continue }
        let scene = String(stem[stem.index(after: dash)...])
        if let sceneFilter, scene != sceneFilter { continue }
        // Hidden scenes are composition sources (extra device shots) only; an
        // explicit --scene still renders them for editor previews.
        if sceneFilter == nil,
           ((scenes[scene] as? [String: Any])?["hidden"] as? Bool) == true { continue }
        guard let screenshot = sprite(at: "\(dir)/\(png)") else {
            FileHandle.standardError.write("warning: unreadable \(dir)/\(png)\n".data(using: .utf8)!)
            continue
        }

        guard let cg = CGContext(data: nil, width: Int(canvasW), height: Int(canvasH),
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fail("cannot create canvas")
        }
        cg.translateBy(x: 0, y: canvasH)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

        // Background gradient, top → bottom. NSGradient angles work in the
        // flipped user space here: 90° puts the starting color at the visual
        // top (verified by pixel-sampling a red→green render).
        let top = color(hex: background["top"] as? String ?? "#3AA0FF")
        let bottom = color(hex: background["bottom"] as? String ?? "#0067DF")
        NSGradient(starting: top, ending: bottom)?
            .draw(in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH), angle: 90)

        let sceneConfig = scenes[scene] as? [String: Any]
        let extras = sceneConfig?["extraTexts"] as? [[String: Any]] ?? []
        let sceneImages = sceneConfig?["images"] as? [[String: Any]] ?? []
        let extraDevices = sceneConfig?["devices"] as? [[String: Any]] ?? []
        var painters: [String: () -> Void] = [:]

        // A device instance: screenshot underneath, frame art on top, rotated
        // as a group. Geometry in frame pixel coordinates (offsets.json
        // values), scaled to the target width.
        func devicePainter(shot: Sprite, style: Style, defaultX: CGFloat) -> (() -> Void)? {
            let frameName = style.string("frame", "Apple iPhone 17 Pro Max Deep Blue")
            guard let frame = sprite(at: "\(studioDir)/frames/\(frameName).png") else {
                fail("missing frame art \(studioDir)/frames/\(frameName).png")
            }
            let frameW = style.number("width", 1200)
            let dx = style.number("x", defaultX)
            let dy = style.number("y", 420)
            let s = frameW / frame.pixelWidth
            let frameH = frame.pixelHeight * s
            let screenH = screenWidth * shot.pixelHeight / shot.pixelWidth
            let screenRect = CGRect(x: dx + screenOffsetX * s, y: dy + screenOffsetY * s,
                                    width: screenWidth * s, height: screenH * s)
            let center = CGPoint(x: dx + frameW / 2, y: dy + frameH / 2)
            let rotation = style.number("rotation", 0)
            return {
                withShadow(style, in: cg) {
                    withRotation(rotation, around: center, in: cg) {
                        if screenCornerRadius > 0 {
                            cg.saveGState()
                            NSBezierPath(roundedRect: screenRect,
                                         xRadius: screenCornerRadius * s, yRadius: screenCornerRadius * s).addClip()
                        }
                        shot.image.draw(in: screenRect)
                        if screenCornerRadius > 0 { cg.restoreGState() }
                        frame.image.draw(in: CGRect(x: dx, y: dy, width: frameW, height: frameH))
                    }
                }
            }
        }

        let deviceStyle = Style(section: "device", scene: scene, locale: locale, block: nil)
        painters["device"] = devicePainter(
            shot: screenshot, style: deviceStyle,
            defaultX: (canvasW - deviceStyle.number("width", 1200)) / 2)

        // Extra device instances show another capture from the same locale
        // (e.g. the wind and pressure map layers fanned next to temperature).
        let capturePrefix = String(stem[..<dash])
        for (i, block) in extraDevices.enumerated() {
            let style = Style(section: "device", scene: scene, locale: locale, block: block)
            guard let shotScene = block["shot"] as? String,
                  let shot = sprite(at: "\(dir)/\(capturePrefix)-\(shotScene).png") else {
                FileHandle.standardError.write("warning: missing device shot \(block["shot"] ?? "?") for \(scene)\n".data(using: .utf8)!)
                continue
            }
            painters["device\(i + 1)"] = devicePainter(shot: shot, style: style, defaultX: 200)
        }

        // Caption from title.strings.
        painters["title"] = {
            if let caption = titles[scene], !caption.isEmpty {
                drawText(caption, style: Style(section: "title", scene: scene, locale: locale, block: nil))
            }
        }

        // Extra text blocks carry their styles and per-locale strings inline.
        for (i, block) in extras.enumerated() {
            painters["extra\(i)"] = {
                let texts = block["text"] as? [String: String] ?? [:]
                guard let text = texts[locale] ?? texts["en-US"], !text.isEmpty else { return }
                drawText(text, style: Style(section: "title", scene: scene, locale: locale, block: block))
            }
        }

        // External images, uploaded through the editor into frame-studio/images.
        for (i, block) in sceneImages.enumerated() {
            painters["image\(i)"] = {
                guard let src = block["src"] as? String,
                      let image = sprite(at: "\(studioDir)/\(src)") else {
                    FileHandle.standardError.write("warning: missing image \(block["src"] ?? "?")\n".data(using: .utf8)!)
                    return
                }
                let style = Style(section: "image", scene: scene, locale: locale, block: block)
                let w = style.number("width", 600)
                let rect = CGRect(x: style.number("x", 100), y: style.number("y", 100),
                                  width: w, height: w * image.pixelHeight / image.pixelWidth)
                withShadow(style, in: cg) {
                    withRotation(style.number("rotation", 0),
                                 around: CGPoint(x: rect.midX, y: rect.midY), in: cg) {
                        image.image.draw(in: rect, from: .zero, operation: .sourceOver,
                                         fraction: style.number("opacity", 1),
                                         respectFlipped: true, hints: nil)
                    }
                }
            }
        }

        // Paint order: the scene's stored order first, then anything new in
        // default stacking (devices lowest, then images, then texts).
        let defaultOrder = ["device"] + extraDevices.indices.map { "device\($0 + 1)" }
            + sceneImages.indices.map { "image\($0)" }
            + ["title"] + extras.indices.map { "extra\($0)" }
        var order = (sceneConfig?["order"] as? [String] ?? []).filter { painters[$0] != nil }
        order += defaultOrder.filter { !order.contains($0) }
        for key in order { painters[key]?() }

        NSGraphicsContext.restoreGraphicsState()

        guard let outImage = cg.makeImage() else { fail("render failed for \(png)") }
        let rep = NSBitmapImageRep(cgImage: outImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { fail("png encode failed") }
        let destination = outPath ?? "\(dir)/\(stem)_framed.png"
        try? fm.createDirectory(atPath: (destination as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        guard (try? data.write(to: URL(fileURLWithPath: destination))) != nil else {
            fail("cannot write \(destination)")
        }
        rendered += 1
        print("framed \(destination)")
    }
}

if rendered == 0 { fail("nothing rendered — check --scene/--locale filters") }

// Overview page of the framed deliverables, one section per locale.
if sceneFilter == nil && outPath == nil {
    var sections = ""
    for locale in localeDirs {
        let dir = "\(screenshotsDir)/\(locale)"
        let framed = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix("_framed.png") }.sorted()
        let cards = framed.map {
            "<figure><img src=\"./\(locale)/\($0)\" loading=\"lazy\"><figcaption>\($0)</figcaption></figure>"
        }.joined(separator: "\n")
        sections += "<h2>\(locale)</h2>\n<div class=\"row\">\(cards)</div>\n"
    }
    let html = """
    <!doctype html><html><head><meta charset="utf-8"><title>Oscar° framed screenshots</title>
    <style>
      body{background:#0b1220;color:#eaf0ff;font-family:-apple-system,system-ui,sans-serif;margin:24px}
      h1{font-weight:600} h2{margin-top:32px;text-transform:uppercase;letter-spacing:.04em;color:#9db4ff}
      .row{display:flex;flex-wrap:wrap;gap:16px}
      figure{margin:0;width:240px} img{width:100%;border-radius:14px;box-shadow:0 8px 24px rgba(0,0,0,.5)}
      figcaption{font-size:12px;color:#8a97b8;margin-top:6px;word-break:break-all}
    </style></head><body>
    <h1>Oscar° — framed App Store screenshots</h1>\(sections)</body></html>
    """
    try? html.write(toFile: "\(screenshotsDir)/framed.html", atomically: true, encoding: .utf8)
    print("overview \(screenshotsDir)/framed.html")
}
