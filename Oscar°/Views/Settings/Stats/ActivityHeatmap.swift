import SwiftUI

struct ActivityHeatmap: View {
    let stats: UsageStats

    private static let weeks = 18
    private static let levels: [Double] = [0.3, 0.5, 0.75, 1]

    var body: some View {
        let columns = Self.columns()
        let counts = columns.flatMap { $0 }.compactMap { $0 }.map { stats.dailyOpens[UsageStatsStore.dayKey($0), default: 0] }
        let busiest = max(counts.max() ?? 0, 1)
        let streaks = stats.streaks()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                streak("Aktuelle Serie", days: streaks.current)
                streak("Längste Serie", days: streaks.longest)
            }

            HStack(alignment: .top, spacing: 3) {
                ForEach(columns.indices, id: \.self) { index in
                    VStack(spacing: 3) {
                        monthLabel(columns[index], previous: index > 0 ? columns[index - 1] : nil)
                        ForEach(0..<7, id: \.self) { weekday in
                            cell(columns[index][weekday], busiest: busiest)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(counts.count(where: { $0 > 0 })) aktive Tage in den letzten \(Self.weeks) Wochen"))

            HStack(spacing: 4) {
                Spacer()
                Text("Weniger")
                RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(width: 10, height: 10)
                ForEach(Self.levels, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(.indigo.opacity(level)).frame(width: 10, height: 10)
                }
                Text("Mehr")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func streak(_ title: LocalizedStringKey, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("^[\(days) Tag](inflect: true)")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func monthLabel(_ week: [Date?], previous: [Date?]?) -> some View {
        let first = week.compactMap { $0 }.first
        let previousMonth = previous?.compactMap { $0 }.first.map { Calendar.current.component(.month, from: $0) }
        let startsMonth = first.map { Calendar.current.component(.month, from: $0) != previousMonth } ?? false
        return Color.clear
            .frame(height: 12)
            .overlay(alignment: .leading) {
                if startsMonth, let first {
                    Text(first, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
    }

    private func cell(_ day: Date?, busiest: Int) -> some View {
        let count = day.map { stats.dailyOpens[UsageStatsStore.dayKey($0), default: 0] } ?? 0
        let level = Self.levels[min(Int(Double(count) / Double(busiest) * Double(Self.levels.count - 1)), Self.levels.count - 1)]
        return RoundedRectangle(cornerRadius: 3)
            .fill(count > 0 ? AnyShapeStyle(.indigo.opacity(level)) : AnyShapeStyle(.quaternary))
            .aspectRatio(1, contentMode: .fit)
            .opacity(day == nil ? 0 : 1)
    }

    private static func columns(now: Date = .now) -> [[Date?]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }
        return (0..<weeks).map { week in
            (0..<7).map { offset in
                guard let day = calendar.date(byAdding: .day, value: week * 7 + offset, to: first), day <= today else { return nil }
                return calendar.date(byAdding: .hour, value: 12, to: day)
            }
        }
    }
}
