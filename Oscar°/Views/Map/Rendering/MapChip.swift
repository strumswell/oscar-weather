//
//  MapChip.swift
//  Oscar°
//
//  Capsule chip artwork shared by the map screens: the saved-city conditions
//  chips (picker map annotations + weather map symbol layer) and the value
//  chips of the model temperature/wind layers. One chrome, drawn once here,
//  so every chip family stays visually identical.
//

import UIKit

@MainActor
enum MapChip {
    static let height: CGFloat = 28
    static let padding: CGFloat = 8
    static let spacing: CGFloat = 4
    static let textFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
    static let fill = UIColor(white: 0.13, alpha: 0.92)
    static let stroke = UIColor(white: 1, alpha: 0.35)

    /// A saved city's conditions as a capsule chip: the app's weather icon
    /// (01d…50n assets, same set as the forecast lists) + current temperature,
    /// like a mini weather-map station label.
    static func conditions(iconAsset: String, temperatureText: String) -> UIImage {
        let icon = UIImage(named: iconAsset)
        // Aspect-fit into the nominal box: the icon assets are not square
        // (clouds are up to ~1.4× wider than tall), a fixed square squishes them.
        let iconBox: CGFloat = 21
        let iconSize: CGSize = {
            guard let native = icon?.size, native.width > 0, native.height > 0 else {
                return CGSize(width: iconBox, height: iconBox)
            }
            let scale = min(iconBox / native.width, iconBox / native.height)
            return CGSize(width: native.width * scale, height: native.height * scale)
        }()

        let text = NSAttributedString(
            string: temperatureText,
            attributes: [.font: textFont, .foregroundColor: UIColor.white]
        )
        let textSize = text.size()
        let width = padding + iconSize.width + spacing + textSize.width + padding

        return capsule(width: width) { _ in
            icon?.draw(in: CGRect(
                x: padding,
                y: (height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            ))
            text.draw(at: CGPoint(
                x: padding + iconSize.width + spacing,
                y: (height - textSize.height) / 2
            ))
        }
    }

    /// The city's identity line ("emoji label") composited under a chip or pin.
    /// Baked into the image because the basemap glyph server has no emoji
    /// coverage; the shadow pass stands in for the symbol layers' text halo.
    /// `balancedAnchor` pads the top with the label block's height so a
    /// center-anchored annotation image keeps the base on the coordinate.
    static func labeled(_ base: UIImage, label: String, balancedAnchor: Bool = false) -> UIImage {
        guard !label.isEmpty else { return base }
        let text = NSAttributedString(
            string: label,
            attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.white]
        )
        let textSize = text.size()
        let gap: CGFloat = 3
        let labelBlock = gap + ceil(textSize.height)
        let size = CGSize(
            width: max(base.size.width, ceil(textSize.width)),
            height: base.size.height + labelBlock * (balancedAnchor ? 2 : 1)
        )
        let baseY: CGFloat = balancedAnchor ? labelBlock : 0
        return UIGraphicsImageRenderer(size: size).image { context in
            base.draw(at: CGPoint(x: (size.width - base.size.width) / 2, y: baseY))
            let origin = CGPoint(x: (size.width - textSize.width) / 2, y: baseY + base.size.height + gap)
            context.cgContext.setShadow(
                offset: .zero,
                blur: 2,
                color: UIColor.black.withAlphaComponent(0.8).cgColor
            )
            text.draw(at: origin)
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            text.draw(at: origin)
        }
    }

    /// A sampled grid value in the same capsule: a leading swatch dot in the
    /// palette color of the sampled index + the value text. The dot keeps the
    /// legend-in-context role of the old colored bubbles while the dark capsule
    /// keeps the text white-on-dark over any raster color behind it.
    static func value(text valueText: String, swatch: UIColor) -> UIImage {
        let dotDiameter: CGFloat = 10
        let text = NSAttributedString(
            string: valueText,
            attributes: [.font: textFont, .foregroundColor: UIColor.white]
        )
        let textSize = text.size()
        let width = padding + dotDiameter + spacing + textSize.width + padding

        return capsule(width: width) { _ in
            let dotRect = CGRect(
                x: padding,
                y: (height - dotDiameter) / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            swatch.setFill()
            UIBezierPath(ovalIn: dotRect).fill()
            UIColor(white: 1, alpha: 0.9).setStroke()
            let ring = UIBezierPath(ovalIn: dotRect.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            ring.stroke()

            text.draw(at: CGPoint(
                x: padding + dotDiameter + spacing,
                y: (height - textSize.height) / 2
            ))
        }
    }

    /// A saved city as a small dark disc with its emoji (or a red pin glyph
    /// when none is set) — the fallback while conditions are still loading.
    static func pin(emoji: String?) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let circle = UIBezierPath(ovalIn: rect)
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.35).cgColor
            )
            fill.setFill()
            circle.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            stroke.setStroke()
            circle.lineWidth = 1
            circle.stroke()

            if let emoji, !emoji.isEmpty {
                let text = NSAttributedString(
                    string: emoji,
                    attributes: [.font: UIFont.systemFont(ofSize: 15)]
                )
                let textSize = text.size()
                text.draw(at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ))
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
                if let glyph = UIImage(systemName: "mappin", withConfiguration: config)?
                    .withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                    glyph.draw(in: CGRect(
                        x: (size.width - glyph.size.width) / 2,
                        y: (size.height - glyph.size.height) / 2,
                        width: glyph.size.width,
                        height: glyph.size.height
                    ))
                }
            }
        }
    }

    /// The shared chrome: dark capsule, hairline stroke, soft drop shadow.
    /// Content draws on top inside the closure.
    private static func capsule(width: CGFloat, content: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            let capsule = UIBezierPath(
                roundedRect: CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1),
                cornerRadius: (height - 1) / 2
            )
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.35).cgColor
            )
            fill.setFill()
            capsule.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            stroke.setStroke()
            capsule.lineWidth = 1
            capsule.stroke()

            content(context)
        }
    }
}
