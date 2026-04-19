import CoreGraphics
import UIKit

enum MemberCardStickerAlphaBounds {
    private struct Metrics {
        let bounds: CGRect
        let bottomTrailingAnchor: CGPoint
    }

    private static var cache: [String: Metrics] = [:]

    static func rect(for assetName: String, in size: CGFloat) -> CGRect {
        let normalized = metrics(for: assetName).bounds
        return CGRect(
            x: normalized.minX * size,
            y: normalized.minY * size,
            width: normalized.width * size,
            height: normalized.height * size
        )
    }

    static func bottomTrailingAnchor(for assetName: String, in size: CGFloat) -> CGPoint {
        let normalized = metrics(for: assetName).bottomTrailingAnchor
        return CGPoint(x: normalized.x * size, y: normalized.y * size)
    }

    private static func metrics(for assetName: String) -> Metrics {
        if let cached = cache[assetName] {
            return cached
        }

        guard let image = UIImage(named: MemberCard.imageName(for: assetName)),
              let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            let fallback = Metrics(
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                bottomTrailingAnchor: CGPoint(x: 1, y: 1)
            )
            cache[assetName] = fallback
            return fallback
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = max(cgImage.bitsPerPixel / 8, 4)
        let alphaOffset = alphaByteOffset(for: cgImage.alphaInfo, bytesPerPixel: bytesPerPixel)

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundOpaquePixel = false
        var anchorPixel = CGPoint(x: width - 1, y: height - 1)
        var bestAnchorScore = Int.min

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let alpha = bytes[offset + alphaOffset]

                guard alpha > 12 else { continue }
                foundOpaquePixel = true
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                let score = (x * 10_000) + y
                if score > bestAnchorScore {
                    bestAnchorScore = score
                    anchorPixel = CGPoint(x: x, y: y)
                }
            }
        }

        let metrics: Metrics
        if foundOpaquePixel {
            metrics = Metrics(
                bounds: CGRect(
                    x: CGFloat(minX) / CGFloat(width),
                    y: CGFloat(minY) / CGFloat(height),
                    width: CGFloat((maxX - minX) + 1) / CGFloat(width),
                    height: CGFloat((maxY - minY) + 1) / CGFloat(height)
                ),
                bottomTrailingAnchor: CGPoint(
                    x: min(max((anchorPixel.x + 0.5) / CGFloat(width), 0), 1),
                    y: min(max((anchorPixel.y + 0.5) / CGFloat(height), 0), 1)
                )
            )
        } else {
            metrics = Metrics(
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                bottomTrailingAnchor: CGPoint(x: 1, y: 1)
            )
        }

        cache[assetName] = metrics
        return metrics
    }

    private static func alphaByteOffset(for alphaInfo: CGImageAlphaInfo, bytesPerPixel: Int) -> Int {
        switch alphaInfo {
        case .first, .premultipliedFirst, .noneSkipFirst:
            return 0
        case .last, .premultipliedLast, .noneSkipLast:
            return max(bytesPerPixel - 1, 0)
        default:
            return max(bytesPerPixel - 1, 0)
        }
    }
}
