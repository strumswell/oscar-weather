import SwiftUI
import UIKit

struct MemberCardStickerEditor: View {
    static let coordinateSpaceName = "MemberCardStickerEditorSpace"
    static let dockSpacing: CGFloat = 20
    static let dockPickupHoldDuration: TimeInterval = 0.22
    static let dockPickupAllowableMovement: CGFloat = 12
    static let minimumStickerVisibleRatio: CGFloat = 0.65

    let status: MemberStatus
    let width: CGFloat
    let motion: MemberCardMotion
    let isActive: Bool

    private let stickerStore = MemberCardStickerStore()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dockRevealProgress: CGFloat = 0
    @State private var placements = MemberCardStickerStore().load().filter { MemberCardStickerCatalog.assets.contains($0.assetName) }
    @State private var selectedStickerID: UUID?
    @State private var activeDrag: ActiveDrag?
    @State private var inFlightScaleMultiplier: Double = 1.0
    @State private var inFlightRotationDelta: Angle = .zero
    @State private var settlingStickerID: UUID?
    @State private var settlingStickerFoldProgress: CGFloat = 0

    private var cardHeight: CGFloat {
        width / MemberCardPalette.aspect
    }

    var body: some View {
        VStack(spacing: Self.dockSpacing) {
            surface
                .frame(width: width, height: cardHeight)
                .modifier(MemberCardShadow(motion: motion, cornerRadius: MemberCardPalette.cornerRadius(for: width)))
            if isActive {
                Color.clear
                    .frame(height: MemberCardStickerDock.height)
            }
        }
        .frame(width: width, alignment: .top)
        .overlay(alignment: .topLeading) {
            if isActive {
                overlayLayer
            }
        }
        .coordinateSpace(.named(Self.coordinateSpaceName))
        .simultaneousGesture(
            MagnifyGesture()
                .simultaneously(with: RotateGesture())
                .onChanged { value in
                    guard activeDrag != nil else { return }
                    inFlightScaleMultiplier = Double(value.first?.magnification ?? 1)
                    inFlightRotationDelta = value.second?.rotation ?? .zero
                }
                .onEnded { value in
                    guard activeDrag != nil else { return }
                    inFlightScaleMultiplier = Double(value.first?.magnification ?? 1)
                    inFlightRotationDelta = value.second?.rotation ?? .zero
                }
        )
    }

    private var surface: some View {
        let cardSize = CGSize(width: width, height: cardHeight)
        return MemberCardSurface(
            status: status,
            width: width,
            motion: motion,
            placements: placements,
            activeStickerID: activeDrag?.existingStickerID,
            activeStickerCenter: activeExistingStickerCenter,
            activeStickerScale: activeExistingStickerScale,
            activeStickerRotation: activeExistingStickerRotation,
            settlingStickerID: settlingStickerID,
            settlingStickerFoldProgress: settlingStickerFoldProgress,
            isEditing: isActive,
            onStickerTap: selectSticker,
            onStickerPressChanged: { placement, isPressed in
                updateExistingStickerPress(placement: placement, isPressed: isPressed, in: cardSize)
            },
            onStickerDragChanged: { placement, translation in
                updateExistingStickerDrag(placement: placement, translation: translation, in: cardSize)
            },
            onStickerDragEnded: { placement, translation in
                finishExistingStickerDrag(
                    placement: placement,
                    translation: translation,
                    in: cardSize,
                    removeBinFrame: removeBinFrame(for: cardSize.width)
                )
            }
        )
    }

    @ViewBuilder
    private var overlayLayer: some View {
        GeometryReader { proxy in
            let cardSize = CGSize(width: max(proxy.size.width, 1), height: cardHeight)
            let layoutFrame = proxy.frame(in: .global)
            let removeTargetFrame = removeBinFrame(for: cardSize.width)
            let isHoveringRemoveBin = activeDrag.map { $0.isExisting && removeTargetFrame.contains($0.center) } ?? false

            dockSlot(layoutFrame: layoutFrame, cardSize: cardSize, isHoveringRemoveBin: isHoveringRemoveBin)
                .offset(y: cardHeight)
                .zIndex(10)

            if let activeDrag, activeDrag.isExisting {
                stickerPreview(for: activeDrag)
                    .position(activeDrag.center)
                    .opacity(activeDrag.center.y > cardHeight - 12 ? 1 : 0)
                    .allowsHitTesting(false)
                    .zIndex(300)
            }

            if let activeDrag, activeDrag.isPalette {
                stickerPreview(for: activeDrag)
                    .position(activeDrag.center)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(300)
            }
        }
    }

    @ViewBuilder
    private func dockSlot(layoutFrame: CGRect, cardSize: CGSize, isHoveringRemoveBin: Bool) -> some View {
        MemberCardStickerDock(
                assetNames: MemberCardStickerCatalog.assets,
                activeDragAssetName: activeDrag?.isPalette == true ? activeDrag?.assetName : nil,
                isRemoveTargeted: isHoveringRemoveBin,
                canRemoveSelection: selectedStickerID != nil || activeDrag?.isExisting == true,
                onPickupStarted: { assetName, globalCenter in
                    beginPaletteStickerDrag(assetName: assetName, globalCenter: globalCenter, in: layoutFrame)
                },
                onPickupMoved: { globalCenter in
                    updatePaletteStickerDrag(globalCenter: globalCenter, in: layoutFrame)
                },
                onPickupEnded: { globalCenter in
                    finishPaletteStickerDrag(globalCenter: globalCenter, in: cardSize, layoutFrame: layoutFrame)
                },
                onAccessibleAdd: { assetName in
                    addSticker(assetName: assetName)
                },
                onRemoveSelection: removeSelectedSticker
            )
            .frame(width: cardSize.width, height: MemberCardStickerDock.height)
            .padding(.top, Self.dockSpacing)
            .opacity(dockRevealProgress)
            .scaleEffect(dockRevealScale, anchor: .top)
            .offset(y: closedDockOffset)
            .allowsHitTesting(dockRevealProgress > 0.99)
            .onAppear {
                withAnimation(dockOpenAnimation) {
                    dockRevealProgress = 1
                }
            }
    }

    private var dockOpenAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.22)
    }

    private var dockRevealScale: CGFloat {
        reduceMotion ? 1 : 0.9 + 0.1 * dockRevealProgress
    }

    private var closedDockOffset: CGFloat {
        reduceMotion ? 0 : -18 * (1 - dockRevealProgress)
    }

    private func selectSticker(_ stickerID: UUID) {
        selectedStickerID = stickerID
        bringStickerToFront(stickerID)
    }

    private var activeExistingStickerCenter: CGPoint? {
        guard let activeDrag, activeDrag.isExisting else { return nil }
        return activeDrag.center
    }

    private var activeExistingStickerScale: Double? {
        guard let activeDrag, activeDrag.isExisting else { return nil }
        return clampedScale(activeDrag.baseScale * inFlightScaleMultiplier)
    }

    private var activeExistingStickerRotation: Angle? {
        guard let activeDrag, activeDrag.isExisting else { return nil }
        return Angle(radians: activeDrag.baseRotation) + inFlightRotationDelta
    }

    private func beginPaletteStickerDrag(assetName: String, globalCenter: CGPoint, in layoutFrame: CGRect) {
        settlingStickerID = nil
        settlingStickerFoldProgress = 0
        inFlightScaleMultiplier = 1.0
        inFlightRotationDelta = .zero
        activeDrag = ActiveDrag(
            source: .palette,
            assetName: assetName,
            baseScale: 1.0,
            baseRotation: 0,
            center: localPoint(from: globalCenter, in: layoutFrame)
        )
    }

    private func updatePaletteStickerDrag(globalCenter: CGPoint, in layoutFrame: CGRect) {
        guard activeDrag?.isPalette == true else { return }
        activeDrag?.center = localPoint(from: globalCenter, in: layoutFrame)
    }

    private func resetDrag() {
        activeDrag = nil
        inFlightScaleMultiplier = 1.0
        inFlightRotationDelta = .zero
    }

    private func finishPaletteStickerDrag(globalCenter: CGPoint, in cardSize: CGSize, layoutFrame: CGRect) {
        defer { resetDrag() }

        guard let activeDrag, activeDrag.isPalette else { return }

        let proposedCenter = localPoint(from: globalCenter, in: layoutFrame)
        let finalScale = clampedScale(inFlightScaleMultiplier)
        let allowedCenterBounds = stickerCenterBounds(for: finalScale, in: cardSize)

        guard allowedCenterBounds.contains(proposedCenter) else { return }

        let center = clampedStickerCenter(for: proposedCenter, scale: finalScale, in: cardSize)
        var updatedPlacements = placements
        let nextZIndex = (updatedPlacements.map(\.zIndex).max() ?? 0) + 1
        let sticker = MemberCardStickerPlacement(
            assetName: activeDrag.assetName,
            xRatio: center.x / cardSize.width,
            yRatio: center.y / cardSize.height,
            scale: finalScale,
            rotation: inFlightRotationDelta.radians,
            zIndex: nextZIndex
        )

        updatedPlacements.append(sticker)
        persist(updatedPlacements)
        selectedStickerID = nil
        Haptics.impact()
    }

    private func addSticker(assetName: String) {
        let sticker = MemberCardStickerPlacement(
            assetName: assetName,
            xRatio: 0.5,
            yRatio: 0.5,
            scale: 1,
            rotation: 0,
            zIndex: (placements.map(\.zIndex).max() ?? 0) + 1
        )
        persist(placements + [sticker])
        selectedStickerID = sticker.id
    }

    private func updateExistingStickerPress(placement: MemberCardStickerPlacement, isPressed: Bool, in cardSize: CGSize) {
        guard isPressed else { return }
        updateExistingStickerDrag(placement: placement, translation: .zero, in: cardSize)
    }

    private func updateExistingStickerDrag(placement: MemberCardStickerPlacement, translation: CGSize, in cardSize: CGSize) {
        let origin = stickerCenter(for: placement, in: cardSize)
        let center = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            settlingStickerID = nil
            settlingStickerFoldProgress = 0
            activeDrag = ActiveDrag(source: .existing(placement.id), assetName: placement.assetName, baseScale: placement.scale, baseRotation: placement.rotation, center: center)
        }
    }

    private func finishExistingStickerDrag(
        placement: MemberCardStickerPlacement,
        translation: CGSize,
        in cardSize: CGSize,
        removeBinFrame: CGRect
    ) {
        guard activeDrag?.existingStickerID == placement.id else { return }
        defer { resetDrag() }

        let isTap = abs(translation.width) < 4 && abs(translation.height) < 4 && inFlightScaleMultiplier == 1.0 && inFlightRotationDelta == .zero
        guard !isTap else { return }

        let origin = stickerCenter(for: placement, in: cardSize)
        let proposedCenter = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)

        if removeBinFrame.contains(proposedCenter) {
            removeSticker(placement.id)
            Haptics.impact()
            return
        }

        let finalScale = clampedScale(placement.scale * inFlightScaleMultiplier)
        guard stickerCenterBounds(for: finalScale, in: cardSize).contains(proposedCenter),
              let index = placements.firstIndex(where: { $0.id == placement.id }) else { return }

        let center = clampedStickerCenter(for: proposedCenter, scale: finalScale, in: cardSize)
        var updatedPlacements = placements
        updatedPlacements[index].xRatio = center.x / cardSize.width
        updatedPlacements[index].yRatio = center.y / cardSize.height
        updatedPlacements[index].zIndex = (placements.map(\.zIndex).max() ?? placement.zIndex) + 1
        updatedPlacements[index].scale = finalScale
        updatedPlacements[index].rotation = placement.rotation + inFlightRotationDelta.radians

        persist(updatedPlacements)
        animateStickerFoldDown(for: placement.id)
        selectedStickerID = nil
    }

    private func removeSelectedSticker() {
        guard let selectedStickerID else { return }
        removeSticker(selectedStickerID)
        Haptics.impact()
    }

    private func removeSticker(_ stickerID: UUID) {
        let updatedPlacements = placements.filter { $0.id != stickerID }
        persist(updatedPlacements)

        if selectedStickerID == stickerID {
            selectedStickerID = nil
        }
    }

    private func bringStickerToFront(_ stickerID: UUID) {
        var updatedPlacements = placements

        guard let index = updatedPlacements.firstIndex(where: { $0.id == stickerID }) else { return }

        let highestZIndex = updatedPlacements.map(\.zIndex).max() ?? 0
        guard updatedPlacements[index].zIndex < highestZIndex else { return }

        updatedPlacements[index].zIndex = highestZIndex + 1
        persist(updatedPlacements)
    }

    private func persist(_ updatedPlacements: [MemberCardStickerPlacement]) {
        placements = updatedPlacements
        stickerStore.save(updatedPlacements)
    }

    private func removeBinFrame(for cardWidth: CGFloat) -> CGRect {
        CGRect(x: 0, y: cardHeight + Self.dockSpacing, width: cardWidth, height: MemberCardStickerDock.height)
    }

    private func stickerCenter(for placement: MemberCardStickerPlacement, in size: CGSize) -> CGPoint {
        CGPoint(x: placement.xRatio * size.width, y: placement.yRatio * size.height)
    }

    private func localPoint(from globalPoint: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(x: globalPoint.x - frame.minX, y: globalPoint.y - frame.minY)
    }

    private func clampedStickerCenter(for point: CGPoint, scale: Double, in size: CGSize) -> CGPoint {
        let bounds = stickerCenterBounds(for: scale, in: size)

        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func clampedScale(_ scale: Double) -> Double {
        MemberCardStickerCatalog.clampedScale(scale)
    }

    private func stickerCenterBounds(for scale: Double, in size: CGSize) -> CGRect {
        let stickerSize = MemberCardStickerCatalog.imageSize(for: scale)
        let imageHalfSize = stickerSize / 2
        let minimumVisibleExtent = min(stickerSize * Self.minimumStickerVisibleRatio, min(size.width, size.height))
        let inset = minimumVisibleExtent - imageHalfSize
        let width = max(0, size.width - (inset * 2))
        let height = max(0, size.height - (inset * 2))

        return CGRect(
            x: inset,
            y: inset,
            width: width,
            height: height
        )
    }

    private func stickerPreview(for drag: ActiveDrag) -> some View {
        let displayScale = drag.baseScale * inFlightScaleMultiplier
        let displayRotation = Angle(radians: drag.baseRotation) + inFlightRotationDelta
        let size = MemberCardStickerCatalog.imageSize(for: displayScale)

        return MemberCardStickerArtworkView(
            assetName: drag.assetName,
            size: size,
            foldProgress: drag.isExisting ? 1 : 0
        )
            .rotationEffect(displayRotation)
            .offset(y: reduceMotion ? 0 : -12)
            .shadow(color: .black.opacity(0.28), radius: 20, x: 2, y: 14)
            .scaleEffect(reduceMotion ? 1 : 1.05)
            .accessibilityHidden(true)
    }

    private func animateStickerFoldDown(for stickerID: UUID) {
        settlingStickerID = stickerID
        settlingStickerFoldProgress = 1

        withAnimation(.easeOut(duration: reduceMotion ? 0.14 : 0.22)) {
            settlingStickerFoldProgress = 0
        } completion: {
            if settlingStickerID == stickerID {
                settlingStickerID = nil
            }
        }
    }

}

private extension MemberCardStickerEditor {
    struct ActiveDrag: Equatable {
        enum Source: Equatable {
            case palette
            case existing(UUID)
        }

        let source: Source
        let assetName: String
        let baseScale: Double
        let baseRotation: Double
        var center: CGPoint

        var existingStickerID: UUID? {
            guard case let .existing(stickerID) = source else { return nil }
            return stickerID
        }

        var isExisting: Bool {
            existingStickerID != nil
        }

        var isPalette: Bool {
            !isExisting
        }
    }
}
