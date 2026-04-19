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
    let onRemoveSelection: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .accessibilityElement(children: .contain)
    }

    private var stickerRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stickers")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.62))
                .padding(.leading, 16)

            MemberCardStickerDockBridge(
                assetNames: assetNames,
                activeDragAssetName: activeDragAssetName,
                onPickupStarted: onPickupStarted,
                onPickupMoved: onPickupMoved,
                onPickupEnded: onPickupEnded
            )
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .padding(.leading, 0)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .padding(.top, 12)
        .padding(.bottom, 12)
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

private struct MemberCardStickerDockBridge: UIViewRepresentable {
    let assetNames: [String]
    let activeDragAssetName: String?
    let onPickupStarted: (String, CGPoint) -> Void
    let onPickupMoved: (CGPoint) -> Void
    let onPickupEnded: (CGPoint) -> Void

    func makeUIView(context: Context) -> MemberCardStickerDockScrollView {
        let dockView = MemberCardStickerDockScrollView()
        dockView.onPickupStarted = onPickupStarted
        dockView.onPickupMoved = onPickupMoved
        dockView.onPickupEnded = onPickupEnded
        dockView.assetNames = assetNames
        dockView.activeDragAssetName = activeDragAssetName
        return dockView
    }

    func updateUIView(_ uiView: MemberCardStickerDockScrollView, context: Context) {
        uiView.onPickupStarted = onPickupStarted
        uiView.onPickupMoved = onPickupMoved
        uiView.onPickupEnded = onPickupEnded
        uiView.assetNames = assetNames
        uiView.activeDragAssetName = activeDragAssetName
    }
}

private final class MemberCardStickerDockScrollView: UIView {
    var onPickupStarted: ((String, CGPoint) -> Void)?
    var onPickupMoved: ((CGPoint) -> Void)?
    var onPickupEnded: ((CGPoint) -> Void)?

    var assetNames: [String] = [] {
        didSet {
            guard assetNames != oldValue else { return }
            rebuildStickerViews()
        }
    }

    var activeDragAssetName: String? {
        didSet {
            guard activeDragAssetName != oldValue else { return }
            updateActiveState()
        }
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var stickerViews: [MemberCardDockStickerItemView] = []
    private var activePickupAssetName: String?

    private lazy var pickupGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePickupGesture(_:)))
        recognizer.minimumPressDuration = MemberCard.dockPickupHoldDuration
        recognizer.allowableMovement = MemberCard.dockPickupAllowableMovement
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
        rebuildStickerViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handlePickupGesture(_ recognizer: UILongPressGestureRecognizer) {
        let stackLocation = recognizer.location(in: stackView)
        let selfLocation = recognizer.location(in: self)
        let globalLocation = convertToGlobalPoint(selfLocation)

        switch recognizer.state {
        case .began:
            guard let stickerView = stickerView(at: stackLocation) else { return }
            activePickupAssetName = stickerView.assetName
            scrollView.isScrollEnabled = false
            onPickupStarted?(stickerView.assetName, globalLocation)
        case .changed:
            guard activePickupAssetName != nil else { return }
            onPickupMoved?(globalLocation)
        case .ended:
            finishPickup(at: globalLocation)
        case .cancelled, .failed:
            finishPickup(at: globalLocation)
        default:
            break
        }
    }

    private func finishPickup(at globalLocation: CGPoint) {
        defer {
            scrollView.isScrollEnabled = true
            activePickupAssetName = nil
        }

        guard activePickupAssetName != nil else { return }
        onPickupEnded?(globalLocation)
    }

    private func setUpViewHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = -1
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        addGestureRecognizer(pickupGestureRecognizer)
    }

    private func rebuildStickerViews() {
        for arrangedSubview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        stickerViews = assetNames.map { assetName in
            let stickerView = MemberCardDockStickerItemView(assetName: assetName)
            stickerView.translatesAutoresizingMaskIntoConstraints = false
            stickerView.widthAnchor.constraint(equalToConstant: MemberCard.dockStickerTouchSize).isActive = true
            stickerView.heightAnchor.constraint(equalToConstant: MemberCard.dockStickerTouchSize).isActive = true
            stackView.addArrangedSubview(stickerView)
            return stickerView
        }

        updateActiveState()
    }

    private func updateActiveState() {
        for stickerView in stickerViews {
            stickerView.isActive = stickerView.assetName == activeDragAssetName
        }
    }

    private func stickerView(at point: CGPoint) -> MemberCardDockStickerItemView? {
        stickerViews.first { $0.frame.insetBy(dx: -8, dy: -8).contains(point) }
    }

    private func convertToGlobalPoint(_ point: CGPoint) -> CGPoint {
        guard let window else { return convert(point, to: nil) }
        return convert(point, to: window)
    }
}

private final class MemberCardDockStickerItemView: UIView {
    let assetName: String

    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            updateActiveAppearance()
        }
    }

    private let imageView = UIImageView()

    init(assetName: String) {
        self.assetName = assetName
        super.init(frame: .zero)
        setUpViewHierarchy()
        updateActiveAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpViewHierarchy() {
        isAccessibilityElement = true
        accessibilityLabel = MemberCard.stickerTitle(for: assetName)
        accessibilityHint = "Press and hold, then drag onto the member card."

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(named: MemberCard.imageName(for: assetName))
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func updateActiveAppearance() {
        let shadowOpacity: Float = isActive ? 0.18 : 0.08
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = shadowOpacity
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 8)
        transform = isActive ? CGAffineTransform(scaleX: 1.12, y: 1.12) : .identity
    }
}
