import SwiftUI

struct MemberCardSurface: View {
    let status: MemberStatus
    var hidesNewestStamp = false
    var slamTrigger = 0
    let width: CGFloat
    let motion: MemberCardMotion
    let placements: [MemberCardStickerPlacement]
    var activeStickerID: UUID?
    var activeStickerCenter: CGPoint?
    var activeStickerScale: Double?
    var activeStickerRotation: Angle?
    var settlingStickerID: UUID?
    var settlingStickerFoldProgress: CGFloat = 0
    var isEditing = false
    var onStickerTap: (UUID) -> Void = { _ in }
    var onStickerPressChanged: (MemberCardStickerPlacement, Bool) -> Void = { _, _ in }
    var onStickerDragChanged: (MemberCardStickerPlacement, CGSize) -> Void = { _, _ in }
    var onStickerDragEnded: (MemberCardStickerPlacement, CGSize) -> Void = { _, _ in }

    var body: some View {
        let stamps = status.stamps
        ZStack {
            MemberCardFace(
                tier: status.style,
                title: status.title,
                since: status.since,
                stamps: stamps,
                hiddenStampID: hidesNewestStamp ? stamps.last?.id : nil,
                slamTrigger: slamTrigger,
                width: width,
                motion: motion
            )
            stickerLayer
        }
        .frame(width: width, height: width / MemberCardPalette.aspect)
    }

    private var stickerLayer: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(placements) { placement in
                    let displayPlacement = displayedPlacement(for: placement, in: proxy.size)
                    MemberCardPlacedStickerView(
                        placement: displayPlacement,
                        isEditing: isEditing,
                        isGestureLocked: activeStickerID != nil && activeStickerID != placement.id,
                        foldProgress: foldProgress(for: placement.id),
                        coordinateSpaceName: MemberCardStickerEditor.coordinateSpaceName,
                        onTap: {
                            onStickerTap(placement.id)
                        },
                        onPressChanged: { isPressed in
                            onStickerPressChanged(placement, isPressed)
                        },
                        onDragChanged: { translation in
                            onStickerDragChanged(placement, translation)
                        },
                        onDragEnded: { translation in
                            onStickerDragEnded(placement, translation)
                        }
                    )
                    .position(
                        x: displayPlacement.xRatio * proxy.size.width,
                        y: displayPlacement.yRatio * proxy.size.height
                    )
                    .zIndex(activeStickerID == placement.id ? 400 : displayPlacement.zIndex)
                    .opacity(activeStickerID == placement.id && shouldShowActiveStickerOverlay(in: proxy.size) ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func shouldShowActiveStickerOverlay(in size: CGSize) -> Bool {
        guard let activeStickerCenter else { return false }
        return activeStickerCenter.y > size.height - 12
    }

    private func displayedPlacement(for placement: MemberCardStickerPlacement, in size: CGSize) -> MemberCardStickerPlacement {
        guard activeStickerID == placement.id,
              let activeStickerCenter,
              let activeStickerScale else {
            return placement
        }

        var updatedPlacement = placement
        updatedPlacement.xRatio = activeStickerCenter.x / max(size.width, 1)
        updatedPlacement.yRatio = activeStickerCenter.y / max(size.height, 1)
        updatedPlacement.scale = activeStickerScale
        updatedPlacement.rotation = activeStickerRotation?.radians ?? placement.rotation
        updatedPlacement.zIndex = max(placement.zIndex, placements.map(\.zIndex).max() ?? placement.zIndex)
        return updatedPlacement
    }

    private func foldProgress(for stickerID: UUID) -> CGFloat {
        if activeStickerID == stickerID {
            return 1
        }

        if settlingStickerID == stickerID {
            return settlingStickerFoldProgress
        }

        return 0
    }
}
