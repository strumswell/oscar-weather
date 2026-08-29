import SwiftUI

/// The hourly sheet's second reading: the forecast as a vertical timeline of
/// chapters. Scrolling scrubs the sim to the chapter passing the viewport
/// center; tapping glides there and expands the chapter in place.
struct HourlyChaptersView: View {
    let model: HourlyTimelineModel

    @State private var expandedID: String?
    @State private var centerItemID: String?
    @State private var scrollPhase: ScrollPhase = .idle

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
                    switch item {
                    case .divider(_, let label):
                        dayDivider(label)
                    case .chapter(let chapter):
                        chapterRow(chapter, now: now)
                    }
                }
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
                .font(.system(size: 12, weight: .bold))
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
        .onAppear {
            guard centerItemID == nil else { return }
            let timeline = model.chapters.filter { $0.kind != .day }
            centerItemID = (timeline.last(where: { $0.range.lowerBound <= model.scrubTime })
                ?? timeline.first)?.id
        }
        .onChange(of: centerItemID) { _, id in
            let userIsScrolling = scrollPhase == .tracking
                || scrollPhase == .interacting
                || scrollPhase == .decelerating
            guard userIsScrolling,
                  let chapter = model.chapters.first(where: { $0.id == id }),
                  chapter.kind != .day else { return }
            model.glide(to: chapter.jumpTime)
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

    private var items: [Item] {
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
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .fixedSize()

            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.leading, 34)
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Chapter rows

    private func chapterRow(_ chapter: ChapterEngine.Chapter, now: Double) -> some View {
        let isExpanded = expandedID == chapter.id
        let isPast = chapter.range.upperBound < now
        return HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(tint(for: chapter))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 22, alignment: .center)
            .padding(.top, 21)

            card(chapter, isExpanded: isExpanded)
                .scrollTransition { [isExpanded] content, phase in
                    content.opacity(phase.isIdentity || isExpanded ? 1 : 0.5)
                }
        }
        .opacity(isPast ? 0.55 : 1)
        .onDisappear {
            if expandedID == chapter.id {
                expandedID = nil
            }
        }
        .id(chapter.id)
    }

    private func card(_ chapter: ChapterEngine.Chapter, isExpanded: Bool) -> some View {
        VStack(spacing: 10) {
            Button {
                guard scrollPhase == .idle else { return }
                let expands = !isExpanded && isExpandable(chapter)
                withAnimation(.snappy) {
                    expandedID = expands ? chapter.id : nil
                    if expands {
                        centerItemID = chapter.id
                    }
                }
                model.glide(to: chapter.jumpTime)
            } label: {
                cardHeader(chapter)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(expandHint(for: chapter, isExpanded: isExpanded))

            if isExpanded {
                expandedContent(chapter)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func expandedContent(_ chapter: ChapterEngine.Chapter) -> some View {
        if chapter.kind == .alert {
            Text(verbatim: chapter.detail ?? "")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 10) {
                if let legend = legend(for: chapter) {
                    legendRow(legend)
                }
                HourlyChapterChart(model: model, chapter: chapter)
                    .frame(height: 104)
                let stats = stats(for: chapter)
                if !stats.isEmpty {
                    statsRow(stats)
                }
            }
        }
    }

    private func cardHeader(_ chapter: ChapterEngine.Chapter) -> some View {
        let tint = tint(for: chapter)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.22))
                    .frame(width: 34, height: 34)
                Image(systemName: chapter.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor(for: chapter))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: chapter.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !chapter.subtitle.isEmpty {
                    Text(verbatim: chapter.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !chapter.valueLabel.isEmpty {
                Text(verbatim: chapter.valueLabel)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor(for: chapter))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [chapter.title, chapter.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")))
        .accessibilityValue(Text(verbatim: chapter.valueLabel))
    }

    private func legendRow(_ legend: [(color: Color, label: String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(legend.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 7, height: 7)
                    Text(verbatim: entry.label)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            Spacer()
        }
    }

    private func statsRow(_ stats: [(label: LocalizedStringKey, value: String)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.label)
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: stat.value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Chapter styling

    private func expandHint(for chapter: ChapterEngine.Chapter, isExpanded: Bool) -> Text {
        guard isExpandable(chapter) else { return Text(verbatim: "") }
        if chapter.kind == .alert {
            return isExpanded ? Text("Klappt die Details ein") : Text("Zeigt die Details")
        }
        return isExpanded ? Text("Klappt das Diagramm ein") : Text("Zeigt das Diagramm")
    }

    private func isExpandable(_ chapter: ChapterEngine.Chapter) -> Bool {
        switch chapter.kind {
        case .sunEvent: false
        case .alert: chapter.detail != nil
        case .precipitation, .radar, .wind, .night, .day: true
        }
    }

    private func tint(for chapter: ChapterEngine.Chapter) -> Color {
        switch chapter.kind {
        case .precipitation, .radar:
            chapter.systemImage.contains("snow") ? .cyan : .hourlyRain
        case .wind:
            .teal
        case .night:
            Color(red: 0.66, green: 0.72, blue: 1)
        case .sunEvent:
            .orange
        case .alert:
            AlertSeverityStyle.color(rank: chapter.severityRank ?? 1, source: chapter.severitySource)
        case .day:
            switch chapter.systemImage {
            case "sun.max.fill", "cloud.sun.fill": .yellow
            case "cloud.rain.fill", "cloud.heavyrain.fill", "cloud.drizzle.fill",
                 "cloud.bolt.rain.fill": .hourlyRain
            case "cloud.snow.fill": .cyan
            default: .hourlyCloud
            }
        }
    }

    private func iconColor(for chapter: ChapterEngine.Chapter) -> Color {
        let tint = tint(for: chapter)
        switch chapter.kind {
        case .precipitation, .radar, .night: return tint.mix(with: .white, by: 0.35)
        default: return tint
        }
    }

    private func valueColor(for chapter: ChapterEngine.Chapter) -> Color {
        switch chapter.kind {
        case .precipitation, .radar: Color.hourlyRain.mix(with: .white, by: 0.4)
        default: .white.opacity(0.9)
        }
    }

    // MARK: - Expanded content data

    private func legend(for chapter: ChapterEngine.Chapter) -> [(color: Color, label: String)]? {
        switch chapter.kind {
        case .precipitation:
            [(color: .hourlyRain, label: String(localized: "Regen") + " \(model.precipitationUnit)/h"),
             (color: .teal, label: String(localized: "Böen") + " \(model.windUnitString)")]
        case .wind:
            [(color: .teal, label: String(localized: "Böen") + " \(model.windUnitString)"),
             (color: Color.teal.mix(with: .black, by: 0.35), label: String(localized: "Wind"))]
        case .day:
            [(color: .orange, label: String(localized: "Temperatur")),
             (color: .hourlyRain, label: String(localized: "Regen"))]
                + chapter.highlights.map { highlight in
                    switch highlight {
                    case .pressure: (color: .purple, label: String(localized: "Luftdruck"))
                    }
                }
        case .radar, .night, .sunEvent, .alert:
            nil
        }
    }

    private func stats(for chapter: ChapterEngine.Chapter) -> [(label: LocalizedStringKey, value: String)] {
        guard let indices = model.hourIndices(
            from: chapter.range.lowerBound, until: chapter.range.upperBound
        ) else { return [] }
        let times = model.times

        func peak(_ values: [Double]) -> (time: Double, value: Double)? {
            let candidates = indices.filter { $0 < values.count }
            guard let best = candidates.max(by: { values[$0] < values[$1] }) else { return nil }
            return (times[best], values[best])
        }
        func series(_ values: [Double]) -> [Double] {
            indices.compactMap { $0 < values.count ? values[$0] : nil }
        }
        func timedValue(_ moment: (time: Double, value: Double), _ format: (Double) -> String) -> String {
            HourlyFormatting.hourString(timestamp: moment.time, timeZone: model.timeZone)
                + " · " + format(moment.value)
        }

        switch chapter.kind {
        case .precipitation:
            var stats: [(label: LocalizedStringKey, value: String)] = [
                (label: "Summe", value: HourlyFormatting.precipitationString(
                    value: series(model.precipitation).reduce(0, +),
                    unit: model.precipitationUnit
                )),
            ]
            if let peakGust = peak(model.windgusts) {
                stats.append(("Böen", windString(peakGust.value)))
            }
            return stats
        case .wind:
            var stats: [(label: LocalizedStringKey, value: String)] = []
            if let peakGust = peak(model.windgusts) {
                stats.append(("Spitze", timedValue(peakGust, windString)))
            }
            stats.append(("Dauer", durationString(chapter.range)))
            return stats
        case .night:
            var stats: [(label: LocalizedStringKey, value: String)] = []
            if let low = series(model.temperature).min() {
                stats.append(("Tief", HourlyFormatting.temperatureString(low)))
            }
            let clouds = series(model.cloudcover)
            if !clouds.isEmpty {
                stats.append(("Bewölkung", "\(Int((clouds.reduce(0, +) / Double(clouds.count)).rounded()))%"))
            }
            stats.append(("Dauer", durationString(chapter.range)))
            return stats
        case .day:
            var stats: [(label: LocalizedStringKey, value: String)] = [
                (label: "Regen", value: HourlyFormatting.precipitationString(
                    value: series(model.precipitation).reduce(0, +),
                    unit: model.precipitationUnit
                )),
            ]
            for highlight in chapter.highlights {
                switch highlight {
                case .pressure:
                    let pressures = series(model.pressure)
                    if let first = pressures.first, let last = pressures.last {
                        stats.append(("Luftdruck", "\(Int(first.rounded())) → \(Int(last.rounded())) hPa"))
                    }
                }
            }
            return stats
        case .radar, .sunEvent, .alert:
            return []
        }
    }

    private func windString(_ value: Double) -> String {
        HourlyFormatting.windString(
            value,
            unit: WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit),
            unitString: model.windUnitString
        )
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func durationString(_ range: ClosedRange<Double>) -> String {
        Self.durationFormatter.string(from: range.upperBound - range.lowerBound) ?? ""
    }
}
