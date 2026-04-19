import SwiftUI

struct MemberCardStickerArtworkView: View {
    let assetName: String
    let size: CGFloat
    let foldProgress: CGFloat

    var body: some View {
        let opaqueBounds = MemberCardStickerAlphaBounds.rect(for: assetName, in: size)

        stickerImage(in: opaqueBounds)
    }

    private func stickerImage(in opaqueBounds: CGRect) -> some View {
        baseStickerImage
            .compositingGroup()
            .overlay {
                plasticHighlightOverlay(in: opaqueBounds)
            }
            .overlay {
                plasticDepthOverlay(in: opaqueBounds)
            }
            .overlay {
                plasticEdgeOverlay(in: opaqueBounds)
            }
            .layerEffect(
                stickerPlasticShader,
                maxSampleOffset: .zero
            )
    }

    private var baseStickerImage: some View {
        Image(MemberCard.imageName(for: assetName))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func plasticHighlightOverlay(in opaqueBounds: CGRect) -> some View {
        LinearGradient(
            colors: [
                .white.opacity(0.52),
                .white.opacity(0.18),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: opaqueBounds.width, height: opaqueBounds.height)
        .blur(radius: 2.5)
        .offset(
            x: opaqueBounds.minX + (opaqueBounds.width * 0.04),
            y: opaqueBounds.minY - (opaqueBounds.height * 0.02)
        )
        .mask(stickerMask)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private func plasticDepthOverlay(in opaqueBounds: CGRect) -> some View {
        LinearGradient(
            colors: [
                .clear,
                .black.opacity(0.08),
                .black.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: opaqueBounds.width, height: opaqueBounds.height)
        .blur(radius: 3)
        .offset(x: opaqueBounds.minX, y: opaqueBounds.minY)
        .mask(stickerMask)
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    private func plasticEdgeOverlay(in opaqueBounds: CGRect) -> some View {
        RoundedRectangle(cornerRadius: opaqueBounds.width * 0.26)
            .strokeBorder(.white.opacity(0.34), lineWidth: max(size * 0.012, 0.8))
            .blur(radius: 0.8)
            .frame(width: opaqueBounds.width, height: opaqueBounds.height)
            .offset(x: opaqueBounds.minX, y: opaqueBounds.minY)
            .mask(stickerMask)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    private var stickerMask: some View {
        baseStickerImage
    }

    private var stickerPlasticShader: Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "stickerPlasticSheen"),
            arguments: [.float4(0, 0, Float(size), Float(size))]
        )
    }
}
