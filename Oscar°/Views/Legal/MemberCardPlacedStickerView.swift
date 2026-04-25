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
    let onTransformEnded: (Double, Angle) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var liveTransform: (scale: CGFloat, rotation: Angle) = (1, .zero)
    @State private var liftProgress: CGFloat = 0
    @State private var latestDragTranslation: CGSize = .zero
    @State private var isDraggingSticker = false
    @State private var isTransformingSticker = false

    private var effectiveScale: Double {
        min(max(placement.scale * liveTransform.scale, 0.4), 2.5)
    }

    private var effectiveRotation: Angle {
        Angle(radians: placement.rotation) + liveTransform.rotation
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
                    .simultaneousGesture(transformGesture, including: isGestureLocked ? .none : .all)
                    .accessibilityLabel(MemberCard.stickerTitle(for: placement.assetName))
                    .accessibilityHint("Drag to reposition. Pinch to resize or rotate.")
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
            size: MemberCard.stickerImageSize(for: effectiveScale),
            foldProgress: effectiveFoldProgress
        )
            .rotationEffect(effectiveRotation)
            .padding(MemberCard.stickerTouchPadding)
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .offset(y: liftOffset)
            .scaleEffect(liftedScale)
            .frame(
                width: MemberCard.stickerHitSize(for: effectiveScale),
                height: MemberCard.stickerHitSize(for: effectiveScale)
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
                latestDragTranslation = value.translation
                onDragChanged(value.translation)
            }
            .onEnded { value in
                guard isDraggingSticker else { return }
                if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                    onTap()
                }
                updatePressState(false)
                isDraggingSticker = false
                latestDragTranslation = .zero
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

    private var transformGesture: some Gesture {
        MagnificationGesture()
            .simultaneously(with: RotationGesture())
            .updating($liveTransform) { value, state, _ in
                if !isTransformingSticker {
                    DispatchQueue.main.async {
                        guard !isTransformingSticker else { return }
                        isTransformingSticker = true
                    }
                }
                state.scale = value.first ?? 1
                state.rotation = value.second ?? .zero
            }
            .onEnded { value in
                let scale = Double(value.first ?? 1)
                let rotation = value.second ?? .zero

                if abs(scale - 1) > 0.01 || abs(rotation.radians) > 0.01 {
                    onTransformEnded(
                        scale,
                        rotation
                    )
                }

                updatePressState(false)
                isDraggingSticker = false
                isTransformingSticker = false
                latestDragTranslation = .zero
                onDragEnded(.zero)
            }
    }
}
