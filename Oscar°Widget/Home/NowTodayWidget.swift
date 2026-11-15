//
//  NowTodayWidget.swift
//  Oscar°WidgetExtension
//
//  Created by Philipp Bolte on 03.06.23.
//
import SwiftUI
import WidgetKit

struct NowTodayEntryView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                entry.backgroundGradient
                    .opacity(renderingMode == .accented ? 0 : 1)
            }
            .widgetURL(.oscarPlace(entry.cityID))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            ForecastMediumView(entry: entry)
        case .systemLarge:
            ForecastLargeView(entry: entry)
        default:
            ForecastSmallView(entry: entry)
        }
    }
}

private struct ForecastSmallView: View {
    let entry: HomeEntry
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        if entry.hasRain {
            rain
        } else {
            ForecastCurrentColumn(entry: entry, showsCondition: true)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var rain: some View {
        ViewThatFits(in: .vertical) {
            rainLayout(axis: .span)
            rainLayout(axis: .none)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rainLayout(axis: RainBarsChart.Axis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    ForecastPlaceTitle(entry: entry, font: .subheadline)
                    Spacer(minLength: 0)
                    ForecastConditionIcon(name: entry.icon, size: 20)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(units.temperatureString(entry.temperatureNow))
                        .font(.system(size: 34))
                        .monospacedDigit()
                        .widgetAccentable()
                    Text(verbatim: secondary)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.rainHeadline ?? "")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                RainBarsChart(values: entry.rain, height: 30, axis: axis)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var secondary: String {
        if let rate = entry.rainNow {
            return "\(RainIntensity.format(rate)) \(RainIntensity.unit)"
        }
        return "\(units.temperatureString(entry.temperatureMax)) / \(units.temperatureString(entry.temperatureMin))"
    }
}

private struct ForecastMediumView: View {
    let entry: HomeEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForecastCurrentColumn(entry: entry, showsCondition: !entry.hasRain)
                .frame(width: 112, alignment: .leading)
                .frame(maxHeight: .infinity)

            if entry.hasRain {
                Link(destination: .oscarRadar(entry.cityID)) {
                    ForecastRainBlock(entry: entry, isLarge: false)
                }
            } else {
                VStack(spacing: 0) {
                    if let headline = entry.rainHeadline {
                        Text(headline)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 2)
                    }
                    ForecastHourStrip(hours: entry.hours, isCompact: false)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}

private struct ForecastLargeView: View {
    let entry: HomeEntry
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator
            if entry.hasRain {
                Link(destination: .oscarRadar(entry.cityID)) {
                    ForecastRainBlock(entry: entry, isLarge: true)
                }
                separator
                days(4)
            } else {
                ForecastHourStrip(hours: entry.hours, isCompact: true)
                    .fixedSize(horizontal: false, vertical: true)
                separator
                days(5)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                ForecastPlaceTitle(entry: entry, font: .callout)
                Text(units.temperatureString(entry.temperatureNow))
                    .font(.system(size: 45))
                    .monospacedDigit()
                    .widgetAccentable()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                ForecastConditionIcon(name: entry.icon, size: 22)
                Text(entry.condition)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                ForecastHighLow(entry: entry)
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.25))
            .frame(height: 0.5)
            .padding(.vertical, 10)
    }

    private func days(_ count: Int) -> some View {
        let shown = Array(entry.days.prefix(count))
        let minTemp = shown.map(\.low).min() ?? 0
        let maxTemp = shown.map(\.high).max() ?? 0
        return VStack(spacing: 0) {
            ForEach(shown) { day in
                DailyForecastRow(day: day, minTemp: minTemp, maxTemp: maxTemp)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ForecastCurrentColumn: View {
    let entry: HomeEntry
    let showsCondition: Bool
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        ViewThatFits(in: .vertical) {
            column(inlineIcon: false)
            column(inlineIcon: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func column(inlineIcon: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForecastPlaceTitle(entry: entry, font: .callout)
            Text(units.temperatureString(entry.temperatureNow))
                .font(.system(size: 45))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Spacer(minLength: 0)
            if inlineIcon {
                HStack(spacing: 5) {
                    ForecastConditionIcon(name: entry.icon, size: 16)
                    if showsCondition {
                        condition
                    } else {
                        ForecastHighLow(entry: entry)
                    }
                }
                if showsCondition {
                    ForecastHighLow(entry: entry)
                }
            } else {
                ForecastConditionIcon(name: entry.icon, size: 22)
                    .padding(.bottom, 4)
                if showsCondition {
                    condition
                }
                ForecastHighLow(entry: entry)
            }
        }
    }

    private var condition: some View {
        Text(entry.condition)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct ForecastPlaceTitle: View {
    let entry: HomeEntry
    let font: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.location)
                .font(font.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let staleNote = entry.staleNote {
                Text(staleNote)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }
}

private struct ForecastConditionIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size))
            .frame(height: size)
            .accessibilityHidden(true)
    }
}

private struct ForecastHighLow: View {
    let entry: HomeEntry
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        HStack(spacing: 4) {
            Text("H: \(units.temperatureString(entry.temperatureMax))", comment: "Höchste Temperatur")
            Text("T: \(units.temperatureString(entry.temperatureMin))", comment: "Niedrigste Temperatur")
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.75))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct ForecastHourStrip: View {
    let hours: [ForecastHour]
    let isCompact: Bool
    private var units: Units { SettingService.resolvedUnits }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(hours) { hour in
                VStack(spacing: 0) {
                    Text(hour.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 7)
                    Image(systemName: hour.icon)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: isCompact ? 22 : 26))
                        .frame(height: isCompact ? 22 : 26)
                        .accessibilityHidden(true)
                    Spacer(minLength: 7)
                    Text(units.temperatureString(hour.temperature))
                        .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ForecastRainBlock: View {
    let entry: HomeEntry
    let isLarge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.rainHeadline ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .widgetAccentable()
                    if let detail = entry.rainDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if isLarge, let rate = entry.rainNow {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: RainIntensity.format(rate))
                            .font(.system(size: 26))
                            .monospacedDigit()
                        rateCaption
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLarge ? 8 : 0)

            if !isLarge {
                Spacer(minLength: 4)
                if let rate = entry.rainNow {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: RainIntensity.format(rate))
                            .font(.system(size: 22, weight: .medium))
                            .monospacedDigit()
                        rateCaption
                    }
                    .padding(.bottom, 4)
                }
            }

            RainBarsChart(
                values: entry.rain,
                height: !isLarge && entry.rainNow != nil ? 40 : 52,
                axis: .times(start: entry.date, timeZone: entry.timeZone)
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var rateCaption: some View {
        Text("\(RainIntensity.unit) jetzt")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))
    }
}

struct NowTodayWidget: Widget {
    let kind: String = "TodayWidget"

    var body: some WidgetConfiguration {
        placeConfiguration(kind: kind, source: HomeProvider()) { entry in
            NowTodayEntryView(entry: entry)
        }
        .contentMarginsDisabled()
        .configurationDisplayName(String(localized: "Vorhersage"))
        .description(String(localized: "Aktuelle Wetterbedingungen und Temperaturen für heute."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("Klein", as: .systemSmall) {
    NowTodayWidget()
} timeline: {
    HomeEntry.drySample
    HomeEntry.rainSample
    HomeEntry.rainNowSample
}

#Preview("Mittel", as: .systemMedium) {
    NowTodayWidget()
} timeline: {
    HomeEntry.drySample
    HomeEntry.rainSample
    HomeEntry.rainNowSample
}

#Preview("Groß", as: .systemLarge) {
    NowTodayWidget()
} timeline: {
    HomeEntry.drySample
    HomeEntry.rainSample
    HomeEntry.rainNowSample
}
