import SwiftUI

@MainActor
struct NowLayoutCanvas: View {
    private nonisolated static let space = "layoutCanvas"
    private nonisolated static let row = "layoutRow"
    private let settingsService = SettingService.shared
    private let frames = LayoutFrame.device

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: SectionDrag?
    @State private var columnRects: [ColumnID: CGRect] = [:]
    @State private var blockRects: [BlockID: CGRect] = [:]
    @State private var dockRect: CGRect = .zero
    @State private var rowSize: CGSize?
    @State private var rowRect: CGRect = .zero

    var body: some View {
        VStack(spacing: 16) {
            SkyBand { frameStack }
            dock
        }
        .padding(.horizontal, 16)
        .coordinateSpace(.named(Self.space))
        .overlay { ghost }
    }

    // MARK: Frames

    private var frameStack: some View {
        GeometryReader { geometry in
            let fit = fittingScale(in: geometry.size)
            VStack(spacing: 6) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(frames) { screen($0) }
                }
                .coordinateSpace(.named(Self.row))
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { rowSize = $0 }
                .scaleEffect(fit, anchor: .topLeading)
                .frame(width: (rowSize?.width ?? 0) * fit, height: (rowSize?.height ?? 0) * fit, alignment: .topLeading)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { rowRect = $0 }
                if frames.count > 1 {
                    HStack(spacing: 14 * fit) {
                        ForEach(frames) { frame in
                            Text(frame.title ?? "")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .frame(width: frame.size.width * fit)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(14)
        .frame(maxHeight: .infinity)
        .environment(\.cardBackgroundStyle, stagedCardFill)
        .dynamicTypeSize(.large)
    }

    private func fittingScale(in size: CGSize) -> CGFloat {
        let captions: CGFloat = frames.count > 1 ? 22 : 0
        let natural = rowSize ?? CGSize(
            width: frames.map(\.size.width).reduce(0, +) + CGFloat(frames.count - 1) * 14,
            height: frames.map(\.size.height).max() ?? 1
        )
        return max(min(size.width / natural.width, max(0, size.height - captions) / natural.height, 0.5), 0.05)
    }

    private func screen(_ frame: LayoutFrame) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if frame.isWide {
                column(ColumnID(frame: frame.id, side: .stage))
                column(ColumnID(frame: frame.id, side: .feed))
            } else {
                column(ColumnID(frame: frame.id, side: .page))
            }
        }
        .padding(12)
        .frame(width: frame.size.width, alignment: .top)
        .frame(minHeight: frame.size.height, alignment: .top)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 32))
        .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.35), lineWidth: 6) }
        .clipShape(.rect(cornerRadius: 32))
    }

    private func column(_ id: ColumnID) -> some View {
        let frame = frames[id.frame]
        let run = sections(in: id)
        let others = run.filter { $0 != drag?.section || drag?.source != id.frame }
        let insertion = insertionIndex(in: id)
        return VStack(spacing: 28) {
            if let title = id.side.title {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
            if id.side != .feed {
                PreviewHead()
                    .frame(height: frame.isWide ? 300 : 420)
                    .accessibilityHidden(true)
            }
            ForEach(run) { section in
                if insertion == others.firstIndex(of: section) { insertionBar }
                SectionBlock(section: section, isWide: frame.isWide)
                    .opacity(drag?.section == section && drag?.source == id.frame ? 0.3 : 1)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.row)) }) {
                        blockRects[BlockID(column: id, section: section)] = $0
                    }
                    .overlay { Color.clear.contentShape(.rect).gesture(dragGesture(for: section, from: id.frame)) }
                    .accessibilityActions { blockActions(section, in: id) }
            }
            if insertion == others.count { insertionBar }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: columnHeight(id), alignment: .top)
        .overlay {
            if case .column(let target, _) = drag?.target, target == id {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 6)
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.row)) }) { columnRects[id] = $0 }
    }

    private func columnHeight(_ id: ColumnID) -> CGFloat? {
        let run = sections(in: id)
        guard run.contains(.map) else { return nil }
        let fixed = run.filter { $0 != .map }.compactMap { blockRects[BlockID(column: id, section: $0)]?.height }
        guard fixed.count == run.count - 1 else { return nil }
        let natural = fixed.reduce(0, +) + 140 + 300 + 34 + CGFloat(run.count + 1) * 28
        return max(frames[id.frame].size.height, natural)
    }

    private var insertionBar: some View {
        Capsule()
            .fill(.white)
            .frame(height: 12)
            .padding(.horizontal)
            .shadow(radius: 6)
    }

    // MARK: Dock

    private var dockedSections: [NowSection] {
        NowSection.allCases.filter { section in
            frames.contains { section.renders(wide: $0.isWide) && arrangement(for: $0).hidden.contains(section) }
        }
    }

    private var dock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nicht auf der Seite")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if dockedSections.isEmpty {
                Text("Alle Abschnitte sind auf der Seite. Zieh einen hierher, um ihn auszublenden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 14)], alignment: .leading, spacing: 12) {
                    ForEach(dockedSections) { section in
                        DockChip(section: section)
                            .opacity(drag?.section == section ? 0.3 : 1)
                            .gesture(dragGesture(for: section, from: nil))
                            .accessibilityAction(named: Text("Einfügen")) { insertFromDock(section) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            if drag?.target == .dock {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { dockRect = $0 }
        .animation(motion, value: dockedSections)
    }

    @ViewBuilder
    private var ghost: some View {
        if let drag {
            DockChip(section: drag.section)
                .padding(8)
                .background(.regularMaterial, in: .rect(cornerRadius: 14))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .position(drag.location)
                .allowsHitTesting(false)
        }
    }

    // MARK: Dragging

    private func dragGesture(for section: NowSection, from frameIndex: Int?) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                drag = SectionDrag(section: section, source: frameIndex, location: value.location, target: target(for: section, at: value.location))
            }
            .onEnded { _ in drop() }
    }

    // ponytail: impossible targets show nothing; add a column outline if users miss it.
    private func target(for section: NowSection, at point: CGPoint) -> DropTarget? {
        if dockRect.contains(point) { return .dock }
        guard let rowSize, rowSize.width > 0, rowRect.width > 0 else { return nil }
        let fit = rowRect.width / rowSize.width
        let local = CGPoint(x: (point.x - rowRect.minX) / fit, y: (point.y - rowRect.minY) / fit)
        guard let column = columnRects.first(where: { $0.value.contains(local) })?.key else { return nil }
        guard section.renders(wide: frames[column.frame].isWide), section != .map || column.side == .stage else { return nil }
        let others = sections(in: column).filter { $0 != section }.compactMap { blockRects[BlockID(column: column, section: $0)] }
        return .column(column, index: others.count { $0.midY < local.y })
    }

    private func drop() {
        defer { drag = nil }
        guard let drag, let target = drag.target else { return }
        withAnimation(motion) {
            switch target {
            case .dock:
                hide(drag.section, in: drag.source)
            case .column(let column, let index):
                place(drag.section, at: index, in: column)
            }
        }
        Haptics.impact()
    }

    private var motion: Animation? { reduceMotion ? nil : .snappy }

    private func insertionIndex(in column: ColumnID) -> Int? {
        guard case .column(let target, let index) = drag?.target, target == column else { return nil }
        return index
    }

    private func arrangement(for frame: LayoutFrame) -> SectionArrangement {
        settingsService.arrangement(for: frame.form)
    }

    private func sections(in column: ColumnID) -> [NowSection] {
        let arrangement = arrangement(for: frames[column.frame])
        return switch column.side {
        case .page: arrangement.pageSections
        case .stage: arrangement.stageSections
        case .feed: arrangement.feedSections
        }
    }

    private func hide(_ section: NowSection, in frameIndex: Int?) {
        guard let frameIndex else { return }
        let frame = frames[frameIndex]
        var arrangement = arrangement(for: frame)
        arrangement.hidden.insert(section)
        settingsService.setArrangement(arrangement, for: frame.form)
    }

    // MARK: VoiceOver

    @ViewBuilder
    private func blockActions(_ section: NowSection, in column: ColumnID) -> some View {
        let run = sections(in: column)
        let index = run.firstIndex(of: section) ?? 0
        if index > 0 {
            Button("Nach oben") { place(section, at: index - 1, in: column) }
        }
        if index < run.count - 1 {
            Button("Nach unten") { place(section, at: index + 1, in: column) }
        }
        if column.side == .stage, section != .map {
            Button("Nach rechts") { place(section, at: .max, in: ColumnID(frame: column.frame, side: .feed)) }
        }
        if column.side == .feed {
            Button("Nach links") { place(section, at: .max, in: ColumnID(frame: column.frame, side: .stage)) }
        }
        Button("Ausblenden") {
            withAnimation(motion) { hide(section, in: column.frame) }
        }
    }

    private func insertFromDock(_ section: NowSection) {
        for frame in frames where section.renders(wide: frame.isWide) && arrangement(for: frame).hidden.contains(section) {
            let side: ColumnID.Side = frame.isWide ? (section == .map ? .stage : .feed) : .page
            place(section, at: .max, in: ColumnID(frame: frame.id, side: side))
        }
    }

    private func place(_ section: NowSection, at index: Int, in column: ColumnID) {
        let frame = frames[column.frame]
        var arrangement = arrangement(for: frame)
        withAnimation(motion) {
            arrangement.place(section, at: index, among: sections(in: column), onStage: column.side.onStage)
            settingsService.setArrangement(arrangement, for: frame.form)
        }
    }
}

// MARK: - Pieces

struct LayoutFrame: Identifiable {
    let id: Int
    let title: LocalizedStringResource?
    let size: CGSize

    var form: LayoutForm { LayoutForm.of(size) }
    var isWide: Bool { form.isWide }

    private static let wideWindowKey = "wideWindowSize"

    @MainActor static var device: [LayoutFrame] {
        let screen = (UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)?.screen
        // nativeBounds is portrait whatever the orientation.
        let portrait = screen.map { CGSize(width: $0.nativeBounds.width / $0.nativeScale, height: $0.nativeBounds.height / $0.nativeScale) }
            ?? CGSize(width: 402, height: 874)
        let landscape: CGSize? = if UIDevice.current.userInterfaceIdiom == .pad {
            CGSize(width: portrait.height, height: portrait.width)
        } else if let stored = UserDefaults.standard.array(forKey: wideWindowKey) as? [Double], stored.count == 2 {
            CGSize(width: stored[0], height: stored[1])
        } else {
            nil
        }
        guard let landscape else { return [LayoutFrame(id: 0, title: nil, size: portrait)] }
        return [
            LayoutFrame(id: 0, title: "Hochkant", size: portrait),
            LayoutFrame(id: 1, title: "Quer", size: landscape),
        ]
    }

    // The Duo's open display has no API while it is folded; the forecast's widest window stands in.
    static func rememberWideWindow(_ size: CGSize) {
        guard size.width >= WideForecast.minWidth, size.width > size.height else { return }
        UserDefaults.standard.set([size.width, size.height], forKey: wideWindowKey)
    }
}

private struct ColumnID: Hashable {
    enum Side {
        case page, stage, feed

        var onStage: Bool? {
            switch self {
            case .page: nil
            case .stage: true
            case .feed: false
            }
        }

        var title: LocalizedStringResource? {
            switch self {
            case .page: nil
            case .stage: "Bühne"
            case .feed: "Verlauf"
            }
        }
    }

    let frame: Int
    let side: Side
}

private struct BlockID: Hashable {
    let column: ColumnID
    let section: NowSection
}

private enum DropTarget: Equatable {
    case dock
    case column(ColumnID, index: Int)
}

private struct SectionDrag {
    let section: NowSection
    let source: Int?
    let location: CGPoint
    let target: DropTarget?
}

private struct SectionBlock: View {
    let section: NowSection
    let isWide: Bool

    var body: some View {
        Group {
            switch section {
            case .map:
                Color.clear
                    .cardBackground()
                    .clipShape(.rect(cornerRadius: 10))
                    .cardBorder()
                    .padding(.horizontal)
                    .frame(minHeight: 140, maxHeight: .infinity)
            case .radar:
                RainView()
            case .hourly:
                HourlyView()
            case .daily:
                DailyView(expandsDays: isWide)
            case .environment:
                EnvironmentGaugesView()
            case .climate:
                staged { CollageClimateCard() }
            case .stations:
                staged { StationsCard(stations: OnboardingSampleData.stations, timeZone: .current) { _ in } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(section.title))
    }

    private func staged(@ViewBuilder card: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.leading)
            card()
                .padding(.horizontal)
        }
    }
}

private struct DockChip: View {
    let section: NowSection

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(section.tint.gradient, in: .rect(cornerRadius: 11))
            Text(section.title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
