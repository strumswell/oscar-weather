import SwiftUI
import UIKit

struct MemberCardSurface: View {
    let osName: String
    let osVersion: String
    let placements: [MemberCardStickerPlacement]
    let selectedStickerID: UUID?
    let activeStickerID: UUID?
    let activeStickerCenter: CGPoint?
    let activeStickerScale: Double?
    let activeStickerRotation: Angle?
    let settlingStickerID: UUID?
    let settlingStickerFoldProgress: CGFloat
    let isEditing: Bool
    let isDropTargeted: Bool
    let onCardTap: () -> Void
    let onApplyChanges: () -> Void
    let onStickerTap: (UUID) -> Void
    let onStickerPressChanged: (MemberCardStickerPlacement, Bool) -> Void
    let onStickerDragChanged: (MemberCardStickerPlacement, CGSize) -> Void
    let onStickerDragEnded: (MemberCardStickerPlacement, CGSize) -> Void
    let onStickerTransformEnded: (MemberCardStickerPlacement, Double, Angle) -> Void

    var body: some View {
        ZStack {
            cardBackground
            stickerLayer

            if !isEditing {
                Button(action: onCardTap) {
                    RoundedRectangle(cornerRadius: MemberCard.cornerRadius)
                        .fill(.white.opacity(0.001))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: MemberCard.cornerRadius))
                .accessibilityLabel("Customize member card")
                .accessibilityHint("Opens the sticker dock below the member card.")
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEditing {
                Button(action: onApplyChanges) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .padding(.trailing, 16)
                .accessibilityLabel("Apply changes")
                .accessibilityHint("Closes the sticker editor and keeps your changes.")
            }
        }
        .frame(height: MemberCard.cardHeight)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MemberCard.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.sunnyDayStart, .sunnyDayEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: MemberCard.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.12),
                            .blue.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 180, height: 180)
                .blur(radius: 22)
                .offset(x: -80, y: -95)
                .accessibilityHidden(true)

            Image("cloud5")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 320)
                .opacity(0.72)
                .offset(x: 70, y: -55)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Member")
                                .font(.title2)
                                .bold()
                                .foregroundStyle(.white)
                                .accessibilityLabel("Member status")

                            Image(systemName: "sparkles")
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.top, 2)
                                .accessibilityHidden(true)
                        }

                        Text("Oscar° Club")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    Spacer()

                    Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                        .resizable()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                        .accessibilityHidden(true)
                }

                Spacer()

                HStack {
                    Text("Beta User")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.92))
                        .accessibilityLabel("User type: Beta User")

                    Spacer()
                }

                HStack {
                    Text("\(osName) \(osVersion)")
                        .font(.footnote)
                        .monospaced()
                        .foregroundStyle(.white.opacity(0.95))
                        .accessibilityLabel("Operating system and version: \(osName) \(osVersion)")

                    Spacer()
                }
                .padding(.top, 4)
                }
                .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: MemberCard.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MemberCard.cornerRadius)
                .strokeBorder(
                    .white.opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.2), radius: 22, y: 14)
        .contentShape(RoundedRectangle(cornerRadius: MemberCard.cornerRadius))
    }

    private var stickerLayer: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(placements.sorted(by: { $0.zIndex < $1.zIndex })) { placement in
                    let displayPlacement = displayedPlacement(for: placement, in: proxy.size)
                    MemberCardPlacedStickerView(
                        placement: displayPlacement,
                        isSelected: selectedStickerID == placement.id,
                        isEditing: isEditing,
                        isActivelyDragged: activeStickerID == placement.id,
                        isGestureLocked: activeStickerID != nil && activeStickerID != placement.id,
                        foldProgress: foldProgress(for: placement.id),
                        coordinateSpaceName: MemberCard.coordinateSpaceName,
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
                        },
                        onTransformEnded: { multiplier, rotationDelta in
                            onStickerTransformEnded(placement, multiplier, rotationDelta)
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
