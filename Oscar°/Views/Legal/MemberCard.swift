import SwiftUI
import UIKit

struct MemberCard: View {
    static let cardHeight: CGFloat = 200
    static let cornerRadius: CGFloat = 24
    static let dockHeight: CGFloat = 112
    static let dockSpacing: CGFloat = 14
    static let dockBinSize = CGSize(width: 88, height: 88)
    static let stickerImageBaseSize: CGFloat = 64
    static let stickerTouchPadding: CGFloat = 8
    static let minimumStickerHitSize: CGFloat = 56
    static let dockStickerTouchSize: CGFloat = 86
    static let dockPickupHoldDuration: TimeInterval = 0.22
    static let dockPickupAllowableMovement: CGFloat = 12
    static let minimumStickerVisibleRatio: CGFloat = 0.65
    static let minimumStickerScale: Double = 0.4
    static let maximumStickerScale: Double = 2.5
    static let availableStickerAssets = [
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

    private let os = UIDevice.current.systemName
    private let version = UIDevice.current.systemVersion
    private let stickerStore = MemberCardStickerStore()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var dockRevealProgress: CGFloat = 0
    @State private var placements: [MemberCardStickerPlacement]
    @State private var selectedStickerID: UUID?
    @State private var activeDrag: ActiveDrag?
    @State private var inFlightScaleMultiplier: Double = 1.0
    @State private var inFlightRotationDelta: Angle = .zero
    @State private var settlingStickerID: UUID?
    @State private var settlingStickerFoldProgress: CGFloat = 0

    init() {
        _placements = State(initialValue: MemberCardStickerStore().load())
    }

    var body: some View {
        VStack(spacing: 0) {
            cardBody
                .frame(height: Self.cardHeight)

            dockSpacer
        }
        .frame(height: Self.cardHeight + dockOccupiedHeight)
        .overlay(alignment: .topLeading) {
            overlayLayer
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        // Card-level gesture captures scale+rotation while dragging a sticker.
        .simultaneousGesture(
            MagnificationGesture()
                .simultaneously(with: RotationGesture())
                .onChanged { value in
                    guard activeDrag != nil else { return }
                    inFlightScaleMultiplier = Double(value.first ?? 1)
                    inFlightRotationDelta = value.second ?? .zero
                }
                .onEnded { value in
                    guard activeDrag != nil else { return }
                    inFlightScaleMultiplier = Double(value.first ?? 1)
                    inFlightRotationDelta = value.second ?? .zero
                }
        )
    }

    private var cardBody: some View {
        GeometryReader { proxy in
            let cardSize = CGSize(width: max(proxy.size.width, 1), height: Self.cardHeight)
            let currentDragScale = activeDrag.map { clampedScale($0.baseScale * inFlightScaleMultiplier) }
            let allowedDropFrame = currentDragScale.map { stickerCenterBounds(for: $0, in: cardSize) }
            let canDropOnCard = activeDrag.map { drag in
                allowedDropFrame?.contains(drag.center) ?? false
            } ?? false

            MemberCardSurface(
                osName: os,
                osVersion: version,
                placements: placements,
                selectedStickerID: selectedStickerID,
                activeStickerID: activeDrag?.existingStickerID,
                activeStickerCenter: activeExistingStickerCenter,
                activeStickerScale: activeExistingStickerScale,
                activeStickerRotation: activeExistingStickerRotation,
                settlingStickerID: settlingStickerID,
                settlingStickerFoldProgress: settlingStickerFoldProgress,
                isEditing: isEditing,
                isDropTargeted: canDropOnCard,
                onCardTap: openDock,
                onApplyChanges: closeDock,
                onStickerTap: selectSticker,
                onStickerDragChanged: { placement, translation in
                    updateExistingStickerDrag(placement: placement, translation: translation, in: cardSize)
                },
                onStickerDragEnded: { placement, translation in
                    finishExistingStickerDrag(
                        placement: placement,
                        translation: translation,
                        in: cardSize,
                        removeBinFrame: removeBinFrame(for: cardSize.width).insetBy(dx: -20, dy: -24)
                    )
                },
                onStickerTransformEnded: { placement, multiplier, rotationDelta in
                    transformSticker(placement.id, scaledBy: multiplier, rotatedBy: rotationDelta)
                }
            )
        }
    }

    @ViewBuilder
    private var overlayLayer: some View {
        GeometryReader { proxy in
            let cardSize = CGSize(width: max(proxy.size.width, 1), height: Self.cardHeight)
            let layoutFrame = proxy.frame(in: .global)
            let removeTargetFrame = removeBinFrame(for: cardSize.width).insetBy(dx: -20, dy: -24)
            let isHoveringRemoveBin = activeDrag.map { $0.isExisting && removeTargetFrame.contains($0.center) } ?? false

            dockSlot(layoutFrame: layoutFrame, cardSize: cardSize, isHoveringRemoveBin: isHoveringRemoveBin)
                .offset(y: Self.cardHeight)
                .zIndex(10)

            if let activeDrag, activeDrag.isPalette || activeDrag.isExisting {
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
        if isEditing {
            MemberCardStickerDock(
                assetNames: Self.availableStickerAssets,
                activeDragAssetName: activeDrag?.isPalette == true ? activeDrag?.assetName : nil,
                isRemoveTargeted: isHoveringRemoveBin,
                canRemoveSelection: selectedStickerID != nil,
                onPickupStarted: { assetName, globalCenter in
                    beginPaletteStickerDrag(assetName: assetName, globalCenter: globalCenter, in: layoutFrame)
                },
                onPickupMoved: { globalCenter in
                    updatePaletteStickerDrag(globalCenter: globalCenter, in: layoutFrame)
                },
                onPickupEnded: { globalCenter in
                    finishPaletteStickerDrag(globalCenter: globalCenter, in: cardSize, layoutFrame: layoutFrame)
                },
                onRemoveSelection: removeSelectedSticker
            )
            .frame(height: Self.dockHeight)
            .padding(.top, Self.dockSpacing)
            .opacity(dockRevealProgress)
            .offset(y: closedDockOffset)
            .allowsHitTesting(dockRevealProgress > 0.99)
        }
    }

    private func openDock() {
        guard !isEditing else { return }
        UIApplication.shared.playHapticFeedback()
        isEditing = true
        withAnimation(dockAnimation) {
            dockRevealProgress = 1
        }
    }

    private func closeDock() {
        selectedStickerID = nil
        withAnimation(dockAnimation) {
            dockRevealProgress = 0
            activeDrag = nil
        } completion: {
            guard dockRevealProgress == 0 else { return }
            isEditing = false
        }
    }

    private var dockAnimation: Animation {
        .easeOut(duration: dockAnimationDuration)
    }

    private var dockAnimationDuration: Double {
        reduceMotion ? 0.12 : 0.2
    }

    private var dockOccupiedHeight: CGFloat {
        (Self.dockSpacing + Self.dockHeight) * dockRevealProgress
    }

    private var dockSpacer: some View {
        Color.clear
            .frame(height: dockOccupiedHeight)
    }

    private var closedDockOffset: CGFloat {
        reduceMotion ? 0 : -10 * (1 - dockRevealProgress)
    }

    private func selectSticker(_ stickerID: UUID) {
        selectedStickerID = stickerID
        bringStickerToFront(stickerID)
        UIApplication.shared.playHapticFeedback()
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
        guard let activeDrag, activeDrag.isPalette else { return }
        self.activeDrag = ActiveDrag(
            source: activeDrag.source,
            assetName: activeDrag.assetName,
            baseScale: activeDrag.baseScale,
            baseRotation: activeDrag.baseRotation,
            center: localPoint(from: globalCenter, in: layoutFrame)
        )
    }

    private func finishPaletteStickerDrag(globalCenter: CGPoint, in cardSize: CGSize, layoutFrame: CGRect) {
        defer {
            activeDrag = nil
            inFlightScaleMultiplier = 1.0
            inFlightRotationDelta = .zero
        }

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
        animateStickerFoldDown(for: sticker.id)
        selectedStickerID = nil
        UIApplication.shared.playHapticFeedback()
    }

    private func updateExistingStickerDrag(placement: MemberCardStickerPlacement, translation: CGSize, in cardSize: CGSize) {
        let origin = stickerCenter(for: placement, in: cardSize)
        let center = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)

        if activeDrag?.existingStickerID != placement.id {
            bringStickerToFront(placement.id)
            selectedStickerID = placement.id
        }

        settlingStickerID = nil
        settlingStickerFoldProgress = 0
        activeDrag = ActiveDrag(source: .existing(placement.id), assetName: placement.assetName, baseScale: placement.scale, baseRotation: placement.rotation, center: center)
    }

    private func finishExistingStickerDrag(
        placement: MemberCardStickerPlacement,
        translation: CGSize,
        in cardSize: CGSize,
        removeBinFrame: CGRect
    ) {
        let origin = stickerCenter(for: placement, in: cardSize)
        let proposedCenter = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)

        if removeBinFrame.contains(proposedCenter) {
            activeDrag = nil
            inFlightScaleMultiplier = 1.0
            inFlightRotationDelta = .zero
            removeSticker(placement.id)
            UIApplication.shared.playHapticFeedback()
            return
        }

        let finalScale = clampedScale(placement.scale * inFlightScaleMultiplier)
        let allowedCenterBounds = stickerCenterBounds(for: finalScale, in: cardSize)

        guard allowedCenterBounds.contains(proposedCenter) else {
            activeDrag = nil
            inFlightScaleMultiplier = 1.0
            inFlightRotationDelta = .zero
            return
        }

        let clampedCenter = clampedStickerCenter(for: proposedCenter, scale: finalScale, in: cardSize)
        let finalRotation = placement.rotation + inFlightRotationDelta.radians
        let topZIndex = (placements.map(\.zIndex).max() ?? placement.zIndex) + 1
        var updatedPlacements = placements

        guard let index = updatedPlacements.firstIndex(where: { $0.id == placement.id }) else {
            activeDrag = nil
            inFlightScaleMultiplier = 1.0
            inFlightRotationDelta = .zero
            return
        }

        updatedPlacements[index].xRatio = clampedCenter.x / cardSize.width
        updatedPlacements[index].yRatio = clampedCenter.y / cardSize.height
        updatedPlacements[index].zIndex = topZIndex
        updatedPlacements[index].scale = finalScale
        updatedPlacements[index].rotation = finalRotation

        activeDrag = nil
        persist(updatedPlacements)
        animateStickerFoldDown(for: placement.id)
        selectedStickerID = nil
        inFlightScaleMultiplier = 1.0
        inFlightRotationDelta = .zero
        UIApplication.shared.playHapticFeedback()
    }

    private func transformSticker(_ stickerID: UUID, scaledBy multiplier: Double, rotatedBy delta: Angle) {
        var updatedPlacements = placements
        guard let index = updatedPlacements.firstIndex(where: { $0.id == stickerID }) else { return }
        updatedPlacements[index].scale = clampedScale(updatedPlacements[index].scale * multiplier)
        updatedPlacements[index].rotation += delta.radians
        persist(updatedPlacements)
        UIApplication.shared.playHapticFeedback()
    }

    private func removeSelectedSticker() {
        guard let selectedStickerID else { return }
        removeSticker(selectedStickerID)
        UIApplication.shared.playHapticFeedback()
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
        let binX = max(0, cardWidth - Self.dockBinSize.width)
        let binY = Self.cardHeight + Self.dockSpacing + ((Self.dockHeight - Self.dockBinSize.height) / 2)

        return CGRect(origin: CGPoint(x: binX, y: binY), size: Self.dockBinSize)
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
        min(max(scale, Self.minimumStickerScale), Self.maximumStickerScale)
    }

    private func stickerCenterBounds(for scale: Double, in size: CGSize) -> CGRect {
        let stickerSize = Self.stickerImageSize(for: scale)
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
        let size = Self.stickerImageSize(for: displayScale)

        return MemberCardStickerArtworkView(
            assetName: drag.assetName,
            size: size,
            foldProgress: 1
        )
            .rotationEffect(displayRotation)
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

    static var coordinateSpaceName: String {
        "MemberCardLayoutSpace"
    }

    static func imageName(for assetName: String) -> String {
         return assetName
    }

    static func stickerTitle(for assetName: String) -> String {
        switch assetName {
        case "sticker_sun":
            "Sun sticker"
        case "sticker_grumpy_cloud":
            "Grumpy cloud sticker"
        case "sticker_lightning_bolt":
            "Lightning bolt sticker"
        case "sticker_umbrella":
            "Umbrella sticker"
        case "sticker_oscar":
            "Oscar sticker"
        case "sticker_pest":
            "Pest sticker"
        default:
            "Sticker"
        }
    }

    static func stickerImageSize(for scale: Double) -> CGFloat {
        stickerImageBaseSize * CGFloat(scale)
    }

    static func stickerHitSize(for scale: Double) -> CGFloat {
        max(stickerImageSize(for: scale) + (stickerTouchPadding * 2), minimumStickerHitSize)
    }
}

private extension MemberCard {
    struct ActiveDrag: Equatable {
        enum Source: Equatable {
            case palette
            case existing(UUID)
        }

        let source: Source
        let assetName: String
        let baseScale: Double
        let baseRotation: Double
        let center: CGPoint

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

#Preview(traits: .sizeThatFitsLayout) {
    MemberCard()
        .padding()
}
