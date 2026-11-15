// Next sunrise or sunset with the sun's position on today's arc.
import SwiftUI
import WidgetKit

struct SunEntry: TimelineEntry {
    let date: Date
    let sunrise: Date?
    let sunset: Date?
    var timeZone: TimeZone = .current
    var cityID: String? = nil

    var isDaytime: Bool {
        guard let sunrise, let sunset else { return false }
        return sunrise <= date && date < sunset
    }

    var nextEvent: Date? { isDaytime ? sunset : sunrise }

    var progress: Double? {
        guard isDaytime, let sunrise, let sunset else { return nil }
        return date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }

    var eventLabel: String {
        isDaytime ? String(localized: "Sonnenuntergang") : String(localized: "Sonnenaufgang")
    }

    var eventSymbol: String { isDaytime ? "sunset.fill" : "sunrise.fill" }

    var dayLength: String? {
        guard let sunrise, let sunset else { return nil }
        return Duration.seconds(sunset.timeIntervalSince(sunrise))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    func time(_ date: Date?) -> String {
        date.map { SettingService.formattedTime($0, timeZone: timeZone) } ?? "–"
    }
}

struct SunProvider: PlaceTimelineSource {
    let refreshMinutes = 360

    func placeholder(in context: Context) -> SunEntry {
        let today = Calendar.current.startOfDay(for: Date())
        return SunEntry(
            date: today.addingTimeInterval(14.5 * 3600),
            sunrise: today.addingTimeInterval(7.45 * 3600),
            sunset: today.addingTimeInterval(16.35 * 3600)
        )
    }

    func entries(for place: WidgetPlace, family: WidgetFamily) async throws -> [SunEntry] {
        let (weather, _) = try await WidgetForecast.forecast(place.coordinates)
        let days = zip(weather.daily?.sunrise ?? [], weather.daily?.sunset ?? []).map {
            (sunrise: Date(timeIntervalSince1970: $0), sunset: Date(timeIntervalSince1970: $1))
        }
        let now = Date()
        let end = now.addingTimeInterval(Double(refreshMinutes) * 60)
        let ticks = stride(from: now, to: end, by: 15 * 60)
        let events = days.flatMap { [$0.sunrise, $0.sunset] }.filter { $0 > now && $0 < end }
        return (Array(ticks) + events).sorted().map { date in
            let day = days.first { $0.sunset > date }
            return SunEntry(
                date: date,
                sunrise: day?.sunrise,
                sunset: day?.sunset,
                timeZone: weather.locationTimeZone,
                cityID: place.cityID
            )
        }
    }
}

struct SunWidgetView: View {
    let entry: SunEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(.oscarPlace(entry.cityID))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            SunCircularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            Label {
                Text(verbatim: entry.time(entry.nextEvent))
            } icon: {
                Image(systemName: entry.eventSymbol)
            }
            .accessibilityLabel(Text(verbatim: "\(entry.eventLabel) \(entry.time(entry.nextEvent))"))
            .containerBackground(.clear, for: .widget)
        default:
            SunSmallView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hex: 0x2A2F5E), Color(hex: 0xC98A7A)], startPoint: .top, endPoint: .bottom)
                }
        }
    }
}

private struct SunSmallView: View {
    let entry: SunEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.eventLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text(verbatim: entry.time(entry.nextEvent))
                .font(.system(size: 30))
                .monospacedDigit()
            Spacer(minLength: 0)
            SunArc(progress: entry.progress, lineWidth: 2, dotRadius: 5)
                .frame(height: 54)
            HStack {
                if entry.isDaytime {
                    Text(verbatim: entry.time(entry.sunrise))
                    Spacer(minLength: 4)
                    Text(verbatim: entry.dayLength ?? "")
                } else {
                    Text(verbatim: entry.dayLength ?? "")
                    Spacer(minLength: 4)
                    Text(verbatim: entry.time(entry.sunset))
                }
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .padding(.top, 3)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        [
            "\(entry.eventLabel) \(entry.time(entry.nextEvent))",
            entry.isDaytime ? "\(String(localized: "Sonnenaufgang")) \(entry.time(entry.sunrise))" : "\(String(localized: "Sonnenuntergang")) \(entry.time(entry.sunset))",
            entry.dayLength,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct SunCircularView: View {
    let entry: SunEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                SunArc(progress: entry.progress, lineWidth: 1.5, dotRadius: 3)
                    .frame(width: 40, height: 16)
                Text(verbatim: entry.time(entry.nextEvent))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(entry.eventLabel) \(entry.time(entry.nextEvent))"))
    }
}

private struct SunArc: View {
    let progress: Double?
    let lineWidth: CGFloat
    let dotRadius: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Canvas { context, size in
            let base = size.height - 1
            let amplitude = base - dotRadius
            func point(_ t: Double) -> CGPoint {
                CGPoint(x: dotRadius + t * (size.width - 2 * dotRadius), y: base - sin(.pi * t) * amplitude)
            }
            func arc(to end: Double) -> Path {
                Path { path in
                    path.move(to: point(0))
                    for step in 1...32 {
                        path.addLine(to: point(end * Double(step) / 32))
                    }
                }
            }

            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: base)); $0.addLine(to: CGPoint(x: size.width, y: base)) },
                           with: .color(.white.opacity(0.45)), lineWidth: 1)
            context.stroke(arc(to: 1), with: .color(.white.opacity(0.3)), lineWidth: lineWidth * 0.75)

            guard let progress else { return }
            let t = min(max(progress, 0), 1)
            context.stroke(arc(to: t), with: .color(.white), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            let sun = point(t)
            let dot = CGRect(x: sun.x - dotRadius, y: sun.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(renderingMode == .fullColor ? Color(hex: 0xFFD60A) : .white))
        }
        .accessibilityHidden(true)
    }
}

struct SunWidget: Widget {
    let kind: String = "SunWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: SunProvider()) { entry in
            SunWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Sonne"))
        .description(String(localized: "Nächster Sonnenauf- oder -untergang und der Lauf der Sonne."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

private enum SunPreview {
    static let today = Calendar.current.startOfDay(for: .now)
    static let sunrise = today.addingTimeInterval(7.45 * 3600)
    static let sunset = today.addingTimeInterval(16.35 * 3600)

    static let afternoon = SunEntry(date: today.addingTimeInterval(14.5 * 3600), sunrise: sunrise, sunset: sunset)
    static let morning = SunEntry(date: today.addingTimeInterval(8 * 3600), sunrise: sunrise, sunset: sunset)
    static let night = SunEntry(date: today.addingTimeInterval(5 * 3600), sunrise: sunrise, sunset: sunset)
}

#Preview(as: .systemSmall) {
    SunWidget()
} timeline: {
    SunPreview.afternoon
    SunPreview.morning
    SunPreview.night
}

#Preview(as: .accessoryCircular) {
    SunWidget()
} timeline: {
    SunPreview.afternoon
    SunPreview.night
}

#Preview(as: .accessoryInline) {
    SunWidget()
} timeline: {
    SunPreview.afternoon
}
