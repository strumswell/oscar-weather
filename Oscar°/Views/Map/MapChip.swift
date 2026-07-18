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

    /// A saved city's conditions as a capsule chip: the app's own weather icon
    /// (01d…50n assets, same set as the forecast lists) + current temperature,
    /// like a mini weather-map station label. A custom emoji, when set, leads
    /// the capsule.
    static func conditions(iconAsset: String, temperatureText: String, emoji: String? = nil) -> UIImage {
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

        let emojiText: NSAttributedString? = (emoji?.isEmpty == false)
            ? NSAttributedString(string: emoji ?? "", attributes: [.font: UIFont.systemFont(ofSize: 13)])
            : nil

        let text = NSAttributedString(
            string: temperatureText,
            attributes: [.font: textFont, .foregroundColor: UIColor.white]
        )
        let textSize = text.size()
        let emojiSize = emojiText?.size() ?? .zero
        let emojiAdvance = emojiText == nil ? 0 : emojiSize.width + spacing
        let width = padding + emojiAdvance + iconSize.width + spacing + textSize.width + padding

        return capsule(width: width) { _ in
            emojiText?.draw(at: CGPoint(
                x: padding,
                y: (height - emojiSize.height) / 2
            ))
            icon?.draw(in: CGRect(
                x: padding + emojiAdvance,
                y: (height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            ))
            text.draw(at: CGPoint(
                x: padding + emojiAdvance + iconSize.width + spacing,
                y: (height - textSize.height) / 2
            ))
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
