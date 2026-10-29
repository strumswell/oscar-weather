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

    static let height: CGFloat = 250
    private static let size: CGFloat = 72
    private static let layout: [String: (x: CGFloat, y: CGFloat, tilt: Double)] = [
        "sticker_sun": (0.13, 0.2, -10),
        "sticker_grumpy_cloud": (0.42, 0.14, 6),
        "sticker_lightning_bolt": (0.8, 0.3, -6),
        "sticker_umbrella": (0.25, 0.52, 9),
        "sticker_oscar": (0.55, 0.47, -7),
        "sticker_oscar_sleeping": (0.12, 0.83, -4),
        "sticker_pest": (0.38, 0.82, 7),
        "sticker_solar_panel": (0.63, 0.84, -8),
        "sticker_qourses": (0.88, 0.8, 5)
    ]

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(assetNames, id: \.self) { asset in
                    sticker(asset)
                        .position(center(of: asset, in: area))
                }
                if isRemoveTargeted {
                    removeHint
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .contentShape(.rect)
            .gesture(DockPickupGesture(
                onBegan: { local, global in
                    guard let asset = asset(at: local, in: area),
                          !MemberCardStickerCatalog.isLocked(asset) else { return }
                    Haptics.tick()
                    pickupAssetName = asset
                    onPickupStarted(asset, global)
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
        }
        .overlay(alignment: .topTrailing) {
            if canRemoveSelection {
                Button(action: onRemoveSelection) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Sticker entfernen"))
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: canRemoveSelection)
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isRemoveTargeted)
    }

    @ViewBuilder
    private func sticker(_ asset: String) -> some View {
        let isLifted = asset == activeDragAssetName
        let locked = MemberCardStickerCatalog.isLocked(asset)
        let tilt = Self.layout[asset]?.tilt ?? 0
        let art = Image(decorative: asset)
            .resizable()
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .saturation(locked ? 0 : 1)
            .opacity(locked ? 0.4 : 1)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 3)
            .rotationEffect(.degrees(tilt))
            .scaleEffect(isLifted && !reduceMotion ? 0.4 : (isRemoveTargeted ? 0.92 : 1))
            .opacity(isLifted ? 0 : 1)
            .animation(isLifted ? .easeOut(duration: 0.12) : .spring(duration: 0.5, bounce: 0.5).delay(0.15), value: isLifted)
            .frame(width: Self.size + 16, height: Self.size + 16)

        if locked {
            NavigationLink {
                SupportView()
            } label: {
                art
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(5)
                            .background(.black.opacity(0.55), in: .circle)
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: MemberCardStickerCatalog.title(for: asset)))
            .accessibilityValue(Text("Für Unterstützer:innen"))
        } else {
            art
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: MemberCardStickerCatalog.title(for: asset)))
                .accessibilityAction(named: Text("Auf Karte legen")) {
                    onAccessibleAdd(asset)
                }
        }
    }

    private var removeHint: some View {
        Text("Loslassen zum Entfernen")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func center(of asset: String, in area: CGSize) -> CGPoint {
        let spot = Self.layout[asset] ?? (0.5, 0.5, 0)
        return CGPoint(x: area.width * spot.x, y: area.height * spot.y)
    }

    private func asset(at point: CGPoint, in area: CGSize) -> String? {
        func distance(_ asset: String) -> CGFloat {
            let center = center(of: asset, in: area)
            return hypot(center.x - point.x, center.y - point.y)
        }
        return assetNames
            .filter { distance($0) <= Self.size * 0.65 }
            .min { distance($0) < distance($1) }
    }
}

private struct DockPickupGesture: UIGestureRecognizerRepresentable {
    let onBegan: (CGPoint, CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = MemberCardStickerEditor.dockPickupHoldDuration
        recognizer.allowableMovement = MemberCardStickerEditor.dockPickupAllowableMovement
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
