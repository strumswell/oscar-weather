import SwiftUI

@MainActor
struct NowLayoutCanvas: View {
    private nonisolated static let space = "layoutCanvas"
    private static let gutter: CGFloat = 130
    private static let frameSpacing: CGFloat = 14
    private static let captionHeight: CGFloat = 16
    private let settingsService = SettingService.shared
    private let frames = LayoutFrame.device

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: SectionDrag?
    @State private var screenHeights: [Int: CGFloat] = [:]
    @State private var screenRects: [Int: CGRect] = [:]
    @State private var columnRects: [ColumnID: CGRect] = [:]
    @State private var gutterRects: [ColumnID: CGRect] = [:]
    @State private var blockRects: [BlockID: CGRect] = [:]
    @State private var dockRect: CGRect = .zero

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
            VStack(spacing: Self.frameSpacing) {
                ForEach(frames) { frame in
                    VStack(spacing: 4) {
                        if let title = frame.title {
                            Text(title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                                .frame(height: Self.captionHeight)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            if frame.isWide {
                                callouts(in: ColumnID(frame: frame.id, side: .stage), fit: fit)
                            }
                            scaledScreen(frame, fit: fit)
                            callouts(in: ColumnID(frame: frame.id, side: frame.isWide ? .feed : .page), fit: fit)
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
        let captions = CGFloat(frames.filter { $0.title != nil }.count) * (Self.captionHeight + 4)
        let gaps = CGFloat(frames.count - 1) * Self.frameSpacing
        let height = frames.map { screenHeight($0) }.reduce(0, +)
        let widthFit = frames.map { (size.width - gutters(for: $0)) / $0.size.width }.min() ?? 1
        let heightFit = max(0, size.height - captions - gaps) / height
        return max(min(widthFit, heightFit, 0.5), 0.05)
    }

    private func gutters(for frame: LayoutFrame) -> CGFloat {
        frame.isWide ? 2 * Self.gutter : Self.gutter
    }

    private func screenHeight(_ frame: LayoutFrame) -> CGFloat {
        screenHeights[frame.id] ?? frame.size.height
    }

    private nonisolated static func frameSpace(_ id: Int) -> String {
        "layoutFrame\(id)"
    }

    private func scaledScreen(_ frame: LayoutFrame, fit: CGFloat) -> some View {
        screen(frame, fit: fit)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { screenHeights[frame.id] = $0 }
            .scaleEffect(fit, anchor: .topLeading)
            .frame(width: frame.size.width * fit, height: screenHeight(frame) * fit, alignment: .topLeading)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { screenRects[frame.id] = $0 }
    }

    private func screen(_ frame: LayoutFrame, fit: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if frame.isWide {
                column(ColumnID(frame: frame.id, side: .stage), fit: fit)
                column(ColumnID(frame: frame.id, side: .feed), fit: fit)
            } else {
                column(ColumnID(frame: frame.id, side: .page), fit: fit)
            }
        }
        .padding(12)
        .frame(width: frame.size.width, alignment: .top)
        .frame(minHeight: frame.size.height, alignment: .top)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 32))
        .overlay { RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.35), lineWidth: 6) }
        .clipShape(.rect(cornerRadius: 32))
        .coordinateSpace(.named(Self.frameSpace(frame.id)))
    }

    private func column(_ id: ColumnID, fit: CGFloat) -> some View {
        let space = Self.frameSpace(id.frame)
        let run = sections(in: id)
        let others = run.filter { !isDragged($0, from: id.frame) }
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
                    .padding(.vertical, 24)
                    .accessibilityHidden(true)
            }
            ForEach(run) { section in
                if insertion == others.firstIndex(of: section) { insertionBar }
                SectionBlock(section: section)
                    .opacity(isDragged(section, from: id.frame) ? 0.3 : 1)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) {
                        blockRects[BlockID(column: id, section: section)] = $0
                    }
                    .overlay { Color.clear.contentShape(.rect).gesture(dragGesture(for: section, from: id.frame)) }
                    .overlay(alignment: .topTrailing) { removeButton(section, in: id.frame, fit: fit) }
                    .accessibilityActions { blockActions(section, in: id) }
            }
            if insertion == others.count { insertionBar }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay {
            if case .column(let target, _) = drag?.target, target == id {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 6)
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) { columnRects[id] = $0 }
    }

    private func isDragged(_ section: NowSection, from frameIndex: Int) -> Bool {
        drag?.section == section && drag?.source == frameIndex
    }

    private func removeButton(_ section: NowSection, in frameIndex: Int, fit: CGFloat) -> some View {
        Button {
            withAnimation(motion) { hide(section, in: frameIndex) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10 / fit, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22 / fit, height: 22 / fit)
                .background(.black.opacity(0.4), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private func callouts(in column: ColumnID, fit: CGFloat) -> some View {
        let screenSide: HorizontalEdge = column.side == .stage ? .trailing : .leading
        let alignment: Alignment = screenSide == .trailing ? .topTrailing : .topLeading
        return ZStack(alignment: alignment) {
            ForEach(sections(in: column)) { section in
                if let rect = blockRects[BlockID(column: column, section: section)] {
                    Callout(section: section, screenSide: screenSide)
                        .opacity(isDragged(section, from: column.frame) ? 0.3 : 1)
                        .gesture(dragGesture(for: section, from: column.frame))
                        .offset(y: rect.midY * fit - Callout.height / 2)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: Self.gutter, height: screenHeight(frames[column.frame]) * fit, alignment: alignment)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { gutterRects[column] = $0 }
        .animation(motion, value: blockRects)
        .accessibilityHidden(true)
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
        guard let hit = columnHit(at: point) else { return nil }
        let column = hit.column
        guard section.renders(wide: frames[column.frame].isWide), section != .map || column.side == .stage else { return nil }
        let others = sections(in: column).filter { $0 != section }.compactMap { blockRects[BlockID(column: column, section: $0)] }
        return .column(column, index: others.count { $0.midY < hit.y })
    }

    private func columnHit(at point: CGPoint) -> (column: ColumnID, y: CGFloat)? {
        if let gutter = gutterRects.first(where: { $0.value.contains(point) }) {
            let fit = scale(of: gutter.key.frame)
            return fit > 0 ? (gutter.key, (point.y - gutter.value.minY) / fit) : nil
        }
        guard let screen = screenRects.first(where: { $0.value.contains(point) }) else { return nil }
        let fit = scale(of: screen.key)
        guard fit > 0 else { return nil }
        let x = (point.x - screen.value.minX) / fit
        let column = columnRects.first { $0.key.frame == screen.key && $0.value.minX <= x && x <= $0.value.maxX }?.key
        return column.map { ($0, (point.y - screen.value.minY) / fit) }
    }

    private func scale(of frameIndex: Int) -> CGFloat {
        (screenRects[frameIndex]?.width ?? 0) / frames[frameIndex].size.width
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if section != .map {
                Text(section.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.leading)
            }
            card
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(section.title))
    }

    @ViewBuilder
    private var card: some View {
        switch section {
        case .map:
            Color.clear
                .frame(height: 260)
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
        case .radar:
            PrecipitationSeriesChart(points: OnboardingSampleData.showerPoints, timeZone: .current)
                .padding(16)
                .frame(height: 120)
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
        case .hourly:
            strip(spacing: 12) {
                ForEach(OnboardingSampleData.hourlyItems.prefix(5)) { HourlyForecastCard(item: $0) }
            }
        case .daily:
            CollageDailyCard(dayCount: 3)
                .padding(.horizontal)
        case .stations:
            StationsCard(stations: Array(OnboardingSampleData.stations.prefix(1)), timeZone: .current) { _ in }
                .padding(.horizontal)
        case .environment:
            strip(spacing: 14) {
                ForEach(OnboardingSampleData.gauges) { AQIGaugeCard(metric: $0) }
            }
        case .climate:
            CollageClimateCard()
                .padding(.horizontal)
        }
    }

    private func strip(spacing: CGFloat, @ViewBuilder cards: () -> some View) -> some View {
        HStack(spacing: spacing, content: cards)
            .font(.system(size: 18))
            .fixedSize()
            .padding(.leading)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

private struct Callout: View {
    static let height: CGFloat = 20

    let section: NowSection
    let screenSide: HorizontalEdge

    var body: some View {
        HStack(spacing: 6) {
            if screenSide == .leading { line }
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(section.tint.gradient, in: .rect(cornerRadius: 5))
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if screenSide == .trailing { line }
        }
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .shadow(radius: 2)
        .contentShape(Rectangle().inset(by: -6))
    }

    private var line: some View {
        Rectangle()
            .frame(width: 16, height: 1)
            .opacity(0.6)
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
