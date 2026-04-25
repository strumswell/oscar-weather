import SwiftUI

struct MemberCardStickerArtworkView: View, Animatable {
    let assetName: String
    let size: CGFloat
    var foldProgress: CGFloat

    var animatableData: CGFloat {
        get { foldProgress }
        set { foldProgress = newValue }
    }

    var body: some View {
        let opaqueBounds = MemberCardStickerAlphaBounds.rect(for: assetName, in: size)
        let anchorPoint = MemberCardStickerAlphaBounds.bottomTrailingAnchor(for: assetName, in: size)

        stickerImage(in: opaqueBounds, anchor: anchorPoint)
    }

    private func stickerImage(in opaqueBounds: CGRect, anchor: CGPoint) -> some View {
        ZStack {
            stickerFace(in: opaqueBounds, anchor: anchor)
            stickerBackside(opaqueBounds: opaqueBounds, anchor: anchor)
        }
        .compositingGroup()
    }

    private func stickerFace(in opaqueBounds: CGRect, anchor: CGPoint) -> some View {
        baseStickerImage
            .layerEffect(
                stickerPeelCutoutShader(opaqueBounds: opaqueBounds, anchor: anchor),
                maxSampleOffset: .zero,
                isEnabled: foldProgress > 0
            )
    }

    private func stickerBackside(opaqueBounds: CGRect, anchor: CGPoint) -> some View {
        baseStickerImage
            .layerEffect(
                stickerPeelBacksideShader(opaqueBounds: opaqueBounds, anchor: anchor),
                maxSampleOffset: CGSize(width: size * 0.9, height: size * 0.9),
                isEnabled: foldProgress > 0
            )
            .opacity(foldProgress > 0 ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var baseStickerImage: some View {
        Image(MemberCard.imageName(for: assetName))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }

    private func stickerPeelCutoutShader(opaqueBounds: CGRect, anchor: CGPoint) -> Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "stickerPeelCutout"),
            arguments: peelShaderArguments(opaqueBounds: opaqueBounds, anchor: anchor)
        )
    }

    private func stickerPeelBacksideShader(opaqueBounds: CGRect, anchor: CGPoint) -> Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "stickerPeelBackside"),
            arguments: peelShaderArguments(opaqueBounds: opaqueBounds, anchor: anchor)
        )
    }

    private func peelShaderArguments(opaqueBounds: CGRect, anchor: CGPoint) -> [Shader.Argument] {
        [
            .float4(0, 0, Float(size), Float(size)),
            .float4(Float(opaqueBounds.minX), Float(opaqueBounds.minY),
                    Float(opaqueBounds.width), Float(opaqueBounds.height)),
            .float2(Float(anchor.x), Float(anchor.y)),
            .float(Float(foldProgress))
        ]
    }
}
