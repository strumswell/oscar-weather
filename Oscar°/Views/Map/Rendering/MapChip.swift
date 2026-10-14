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

    static func conditions(iconAsset: String, temperatureText: String) -> UIImage {
        let icon = UIImage(named: iconAsset)
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

    static func webcam(_ photo: UIImage, age: TimeInterval) -> UIImage {
        let margin: CGFloat = 3
        let photoRect = CGRect(x: margin, y: margin, width: 64, height: 36)
        let size = CGSize(width: photoRect.maxX + margin, height: photoRect.maxY + margin)
        let isStale = age > 2 * 3600
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            if isStale {
                cg.setAlpha(0.55)
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            let frame = UIBezierPath(roundedRect: photoRect, cornerRadius: 6)
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            fill.setFill()
            frame.fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.saveGState()
            frame.addClip()
            photo.draw(in: photoRect)
            if isStale {
                UIColor.gray.setFill()
                UIRectFillUsingBlendMode(photoRect, .saturation)
            }
            if age >= 30 * 60 {
                drawAgeTag(age, in: photoRect)
            }
            cg.restoreGState()
            UIColor.white.setStroke()
            frame.lineWidth = 1.5
            frame.stroke()
            if isStale {
                cg.endTransparencyLayer()
            }
        }
    }

    private static func drawAgeTag(_ age: TimeInterval, in photoRect: CGRect) {
        let label = Duration.seconds(age).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 1))
        let text = NSAttributedString(string: label, attributes: [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.white,
        ])
        let textSize = text.size()
        let tag = CGRect(
            x: photoRect.maxX - textSize.width - 8,
            y: photoRect.maxY - textSize.height - 3,
            width: textSize.width + 6,
            height: textSize.height
        )
        UIColor.black.withAlphaComponent(0.65).setFill()
        UIBezierPath(roundedRect: tag, cornerRadius: tag.height / 2).fill()
        text.draw(at: CGPoint(x: tag.minX + 3, y: tag.minY))
    }

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
