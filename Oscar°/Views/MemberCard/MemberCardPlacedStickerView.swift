import SwiftUI

struct MemberCardPlacedStickerView: View {
    let placement: MemberCardStickerPlacement
    let isSelected: Bool
    let isEditing: Bool
    let isActivelyDragged: Bool
    let isGestureLocked: Bool
    let foldProgress: CGFloat
    let coordinateSpaceName: String
    let onTap: () -> Void
    let onPressChanged: (Bool) -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liftProgress: CGFloat = 0
    @State private var isDraggingSticker = false

    private var effectiveScale: Double {
        MemberCardStickerCatalog.clampedScale(placement.scale)
    }

    private var effectiveRotation: Angle {
        Angle(radians: placement.rotation)
    }

    // Peel on card position: lift phase (animates in on press) or settle phase (from external foldProgress)
    private var effectiveFoldProgress: CGFloat {
        max(liftProgress, foldProgress)
    }

    private var shadowOpacity: Double {
        0.12 + Double(liftProgress) * 0.16
    }

    private var shadowRadius: CGFloat {
        8 + liftProgress * 12
    }

    private var shadowY: CGFloat {
        5 + liftProgress * 7
    }

    private var liftedScale: Double {
        reduceMotion ? 1 : 1 + Double(liftProgress) * 0.06
    }

    private var liftOffset: CGFloat {
        reduceMotion ? 0 : -12 * liftProgress
    }

    var body: some View {
        Group {
            if isEditing {
                stickerBody
                    .highPriorityGesture(moveGesture, including: isGestureLocked ? .subviews : .all)
                    .accessibilityLabel(MemberCardStickerCatalog.title(for: placement.assetName))
                    .accessibilityHint("Drag to reposition. While dragging, pinch with a second finger to resize or rotate.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onTap() }
            } else {
                stickerBody
                    .accessibilityHidden(true)
            }
        }
    }

    private var stickerBody: some View {
        MemberCardStickerArtworkView(
            assetName: placement.assetName,
            size: MemberCardStickerCatalog.imageSize(for: effectiveScale),
            foldProgress: effectiveFoldProgress
        )
            .rotationEffect(effectiveRotation)
            .padding(MemberCardStickerCatalog.touchPadding)
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .offset(y: liftOffset)
            .scaleEffect(liftedScale)
            .frame(
                width: MemberCardStickerCatalog.hitSize(for: effectiveScale),
                height: MemberCardStickerCatalog.hitSize(for: effectiveScale)
            )
            .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard !isGestureLocked || isDraggingSticker else { return }
                if !isDraggingSticker {
                    isDraggingSticker = true
                    updatePressState(true)
                }
                onDragChanged(value.translation)
            }
            .onEnded { value in
                guard isDraggingSticker else { return }
                if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                    onTap()
                }
                updatePressState(false)
                isDraggingSticker = false
                onDragEnded(value.translation)
            }
    }

    private func updatePressState(_ isPressed: Bool) {
        withAnimation(isPressed
            ? .spring(duration: 0.2, bounce: 0.25)
            : .spring(duration: 0.18, bounce: 0)
        ) {
            liftProgress = isPressed ? 1 : 0
        }
        onPressChanged(isPressed)
    }
}
