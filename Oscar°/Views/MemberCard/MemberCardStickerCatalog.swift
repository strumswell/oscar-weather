import CoreGraphics
import Foundation

enum MemberCardStickerCatalog {
    static let assets = [
        "sticker_sun",
        "sticker_grumpy_cloud",
        "sticker_lightning_bolt",
        "sticker_umbrella",
        "sticker_oscar",
        "sticker_oscar_sleeping",
        "sticker_pest",
        "sticker_solar_panel",
        "sticker_qourses"
    ]

    static let imageBaseSize: CGFloat = 64
    static let touchPadding: CGFloat = 8
    static let minimumHitSize: CGFloat = 56
    static let minimumScale: Double = 0.4
    static let maximumScale: Double = 2.5

    static func title(for assetName: String) -> String {
        switch assetName {
        case "sticker_sun":
            String(localized: "Sun sticker")
        case "sticker_grumpy_cloud":
            String(localized: "Grumpy cloud sticker")
        case "sticker_lightning_bolt":
            String(localized: "Lightning bolt sticker")
        case "sticker_umbrella":
            String(localized: "Umbrella sticker")
        case "sticker_oscar":
            String(localized: "Oscar sticker")
        case "sticker_pest":
            String(localized: "Pest sticker")
        case "sticker_solar_panel":
            String(localized: "Solar panel sticker")
        case "sticker_qourses":
            String(localized: "Qourses sticker")
        case "sticker_oscar_sleeping":
            String(localized: "Sleeping Oscar sticker")
        default:
            String(localized: "Sticker")
        }
    }

    static func imageSize(for scale: Double) -> CGFloat {
        imageBaseSize * CGFloat(scale)
    }

    static func hitSize(for scale: Double) -> CGFloat {
        max(imageSize(for: scale) + touchPadding * 2, minimumHitSize)
    }

    static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, minimumScale), maximumScale)
    }
}
