import SwiftUI

struct MemberCardPlacedStickerView: View {
    let placement: MemberCardStickerPlacement
    let isSelected: Bool
    let isEditing: Bool
    let isActivelyDragged: Bool
    let foldProgress: CGFloat
    let coordinateSpaceName: String
    let onTap: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    let onTransformEnded: (Double, Angle) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var liveTransform: (scale: CGFloat, rotation: Angle) = (1, .zero)

    private var effectiveScale: Double {
        min(max(placement.scale * liveTransform.scale, 0.4), 2.5)
    }

    private var effectiveRotation: Angle {
        Angle(radians: placement.rotation) + liveTransform.rotation
    }

    var body: some View {
        Group {
            if isEditing {
                stickerBody
                    .onTapGesture { onTap() }
                    .gesture(moveGesture)
                    .simultaneousGesture(transformGesture, including: isActivelyDragged ? .none : .all)
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
            foldProgress: foldProgress
        )
            .opacity(isActivelyDragged ? 0 : 1)
            .rotationEffect(effectiveRotation)
            .padding(MemberCard.stickerTouchPadding)
            .background {
                Circle()
                    .fill(isSelected && isEditing ? .white.opacity(0.14) : .clear)
                    .blur(radius: isSelected && isEditing ? 10 : 0)
            }
            .shadow(
                color: .black.opacity(isSelected && isEditing ? 0.22 : 0.12),
                radius: isSelected && isEditing ? 16 : 8,
                y: isSelected && isEditing ? 10 : 5
            )
            .scaleEffect(isSelected && isEditing && !reduceMotion ? 1.06 : 1)
            .frame(
                width: MemberCard.stickerHitSize(for: effectiveScale),
                height: MemberCard.stickerHitSize(for: effectiveScale)
            )
            .contentShape(Rectangle())
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in onDragChanged(value.translation) }
            .onEnded { value in onDragEnded(value.translation) }
    }

    private var transformGesture: some Gesture {
        MagnificationGesture()
            .simultaneously(with: RotationGesture())
            .updating($liveTransform) { value, state, _ in
                state.scale = value.first ?? 1
                state.rotation = value.second ?? .zero
            }
            .onEnded { value in
                onTransformEnded(
                    Double(value.first ?? 1),
                    value.second ?? .zero
                )
            }
    }
}
