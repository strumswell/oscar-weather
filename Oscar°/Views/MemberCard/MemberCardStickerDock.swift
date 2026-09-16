import SwiftUI
import UIKit

struct MemberCardStickerDock: View {
    let assetNames: [String]
    let activeDragAssetName: String?
    let isRemoveTargeted: Bool
    let canRemoveSelection: Bool
    let onPickupStarted: (String, CGPoint) -> Void
    let onPickupMoved: (CGPoint) -> Void
    let onPickupEnded: (CGPoint) -> Void
    let onAccessibleAdd: (String) -> Void
    let onRemoveSelection: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pickupAssetName: String?
    @State private var railScrollOffset: CGFloat = 0

    private static let itemPitch = MemberCard.dockStickerTouchSize - 1

    var body: some View {
        HStack(spacing: 0) {
            stickerRail

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1)
                .padding(.vertical, 10)

            removeZone
                .frame(width: 92)
        }
        .frame(height: 100)
        .padding(.leading, 2)
        .padding(.trailing, 0)
        .background(dockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
    }

    private var stickerRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stickers")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.62))
                .padding(.leading, 16)

            ScrollView(.horizontal) {
                HStack(spacing: -1) {
                    ForEach(assetNames, id: \.self) { assetName in
                        dockItem(assetName)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Lifted stickers and their shadows may spill above and below the rail,
            // but never sideways into the divider and bin.
            .scrollClipDisabled()
            .mask { Rectangle().padding(.vertical, -32) }
            // The rail stops scrolling the moment a press turns into a pickup.
            .scrollDisabled(pickupAssetName != nil)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, offset in
                railScrollOffset = offset
            }
            .gesture(DockPickupGesture(
                onBegan: { local, global in
                    let index = Int(floor((local.x + railScrollOffset) / Self.itemPitch))
                    guard assetNames.indices.contains(index) else { return }
                    pickupAssetName = assetNames[index]
                    onPickupStarted(assetNames[index], global)
                },
                onMoved: { global in
                    guard pickupAssetName != nil else { return }
                    onPickupMoved(global)
                },
                onEnded: { global in
                    guard pickupAssetName != nil else { return }
                    pickupAssetName = nil
                    onPickupEnded(global)
                }
            ))
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .padding(.leading, 0)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func dockItem(_ assetName: String) -> some View {
        let isActive = assetName == activeDragAssetName
        return Image(decorative: assetName)
            .resizable()
            .scaledToFit()
            .frame(width: MemberCardStickerCatalog.imageBaseSize, height: MemberCardStickerCatalog.imageBaseSize)
            .frame(width: MemberCard.dockStickerTouchSize, height: MemberCard.dockStickerTouchSize)
            .shadow(color: .black.opacity(isActive ? 0.18 : 0.08), radius: 12, y: 8)
            .scaleEffect(isActive && !reduceMotion ? 1.12 : 1)
            .animation(.easeOut(duration: 0.15), value: isActive)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: MemberCardStickerCatalog.title(for: assetName)))
            .accessibilityAction(named: Text("Auf Karte legen")) {
                onAccessibleAdd(assetName)
            }
    }

    private var removeZone: some View {
        Button(action: onRemoveSelection) {
            ZStack {
                binIconBackground
                    .frame(width: 48, height: 48)

                Image(systemName: isRemoveTargeted ? "trash.fill" : "trash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(binForegroundStyle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRemoveSelection)
        .opacity(canRemoveSelection ? 1 : 0.46)
        .accessibilityLabel("Sticker entfernen")
        .accessibilityHint("Removes the currently selected sticker from the member card.")
    }

    private var dockBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    .white.opacity(0.14),
                    .white.opacity(0.05),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    private var binIconBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(isRemoveTargeted ? Color.red.opacity(0.92) : Color.white.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(
                        isRemoveTargeted ? .white.opacity(0.82) : .white.opacity(0.18),
                        lineWidth: isRemoveTargeted ? 1.3 : 1
                    )
            }
            .shadow(color: .black.opacity(isRemoveTargeted ? 0.22 : 0.12), radius: 12, y: 8)
            .scaleEffect(isRemoveTargeted && !reduceMotion ? 1.05 : 1)
    }

    private var binForegroundStyle: AnyShapeStyle {
        isRemoveTargeted ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.92))
    }
}

/// Press-and-hold pickup that coexists with the rail's horizontal scroll: a short
/// hold with little movement lifts a sticker, a swipe keeps scrolling.
private struct DockPickupGesture: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint, CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = MemberCard.dockPickupHoldDuration
        recognizer.allowableMovement = MemberCard.dockPickupAllowableMovement
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let local = context.converter.location(in: .local)
        let global = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            onBegan(local, global)
        case .changed:
            onMoved(global)
        case .ended, .cancelled, .failed:
            onEnded(global)
        default:
            break
        }
    }
}
