import SwiftUI

/// The hourly sheet's second reading: the forecast as a vertical timeline of
/// chapters. Scrolling scrubs the sim to the chapter passing the viewport
/// center; tapping glides there and expands the chapter in place.
struct HourlyChaptersView: View {
    let model: HourlyTimelineModel

    @State private var expandedID: String?
    @State private var centerItemID: String?
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var items: [Item] = []
    @State private var viewportHeight: CGFloat = 0

    private enum Item: Identifiable {
        case divider(id: String, label: String)
        case chapter(ChapterEngine.Chapter)

        var id: String {
            switch self {
            case .divider(let id, _): id
            case .chapter(let chapter): chapter.id
            }
        }
    }

    var body: some View {
        let now = Date.now.timeIntervalSince1970
        let activeID = activeChapterID
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        switch item {
                        case .divider(_, let label):
                            dayDivider(label)
                        case .chapter(let chapter):
                            HourlyChapterRow(
                                chapter: chapter,
                                model: model,
                                isExpanded: expandedID == chapter.id,
                                isActive: activeID == chapter.id,
                                isPast: chapter.range.upperBound < now,
                                onTap: { toggle(chapter) }
                            )
                            .onDisappear {
                                // Re-arm the auto-recenter once an expanded card scrolls out of view.
                                if expandedID == chapter.id {
                                    expandedID = nil
                                }
                            }
                        }
                    }
                }
                // Room below the last chapter so it can reach the center marker.
                Color.clear
                    .frame(height: max(0, viewportHeight * 0.45))
            }
            .scrollTargetLayout()
            .background(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 2)
                    .offset(x: 10)
                    .padding(.vertical, 18)
            }
            .containerRelativeFrame(.horizontal)
        }
        .overlay(alignment: .leading) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1.5)
                .padding(.leading, 21)
                .accessibilityHidden(true)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollPosition(id: $centerItemID, anchor: UnitPoint(x: 0, y: 0.5))
        .onScrollPhaseChange { _, newPhase in
            scrollPhase = newPhase
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .sensoryFeedback(.selection, trigger: centerItemID) { _, _ in scrollPhase != .idle }
        .onChange(of: model.chapters, initial: true) { _, _ in
            items = makeItems()
            guard centerItemID == nil else { return }
            centerItemID = (model.chapters.last(where: { $0.range.lowerBound <= model.scrubTime })
                ?? model.chapters.first)?.id
        }
        .onChange(of: centerItemID) { _, id in
            let userIsScrolling = scrollPhase == .tracking
                || scrollPhase == .interacting
                || scrollPhase == .decelerating
            guard userIsScrolling,
                  let chapter = model.chapters.first(where: { $0.id == id }) else { return }
            // Scrolling should feel like scrubbing: a short ease-out follows the
            // finger instead of the slow-in glide that a tap deserves.
            model.glide(to: chapter.jumpTime, easeOut: true)
        }
        .onChange(of: activeID) { _, id in
            guard expandedID == nil, !model.isGliding, scrollPhase == .idle,
                  let id, id != centerItemID else { return }
            withAnimation(.snappy) {
                centerItemID = id
            }
        }
    }

    private var activeChapterID: String? {
        let time = model.stageTime
        return model.chapters
            .filter { $0.range.contains(time) }
            .min { ($0.range.upperBound - $0.range.lowerBound) < ($1.range.upperBound - $1.range.lowerBound) }?
            .id
    }

    private func makeItems() -> [Item] {
        var calendar = Calendar.current
        calendar.timeZone = model.timeZone

        var items: [Item] = []
        var currentDay: Date?
        for chapter in model.chapters {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: chapter.range.lowerBound))
            if let previous = currentDay, day != previous {
                let label = HourlyFormatting.dayLabel(
                    timestamp: chapter.range.lowerBound,
                    timeZone: model.timeZone,
                    now: .now
                ) + " · " + SettingService.formattedDayMonth(day, timeZone: model.timeZone)
                items.append(.divider(id: "divider-\(Int(day.timeIntervalSince1970))", label: label))
            }
            currentDay = day
            items.append(.chapter(chapter))
        }
        return items
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: 10) {
            // A flat scrim instead of a text shadow: shadows cost an
            // offscreen pass per divider over the live sim.
            Text(verbatim: label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.22), in: Capsule())

            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.leading, 34)
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }

    private func toggle(_ chapter: ChapterEngine.Chapter) {
        guard scrollPhase == .idle else { return }
        let expands = expandedID != chapter.id && chapter.isExpandable
        withAnimation(.snappy) {
            expandedID = expands ? chapter.id : nil
            if expands {
                centerItemID = chapter.id
            }
        }
        model.glide(to: chapter.jumpTime)
    }
}
