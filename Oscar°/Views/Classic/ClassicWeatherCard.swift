//
//  ClassicWeatherCard.swift
//  Oscar°
//
//  The front of the iOS 6 weather card: sun, moon and clouds over the top
//  edge, city and temperature, a horizontal hourly strip for the tapped day,
//  the day rows (scrolling inside the card), and the footer with the map
//  button, update time and the ⓘ button.
//  All sizes are the 320pt-screen originals times `scale`. Dynamic Type is
//  deliberately not applied: the card is a fixed, pixel-driven layout.
//

import SwiftUI

struct ClassicWeatherCard: View {
    let title: String
    let forecast: ClassicForecast?
    let updatedAt: Date?
    let scale: CGFloat
    let onInfo: () -> Void
    let onMap: () -> Void

    @State private var selectedDay = 0

    private var timeZone: TimeZone { forecast?.payload.locationTimeZone ?? .current }

    var body: some View {
        VStack(spacing: 0) {
            header
            if forecast != nil {
                separator
                hourlyStrip
                separator
                ScrollView(.vertical) {
                    dayRows
                }
                .scrollIndicators(.hidden)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxHeight: .infinity)
            }
            footer
        }
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(cardFill)
        .clipShape(.rect(cornerRadius: 10 * scale))
        .overlay(cardShine)
        .overlay(alignment: .top) { heroArt }
        .padding(.top, Self.heroOverhang * scale)
    }

    /// How far the art reaches above the card's top edge (320pt units).
    static let heroOverhang: CGFloat = 36

    // MARK: - Header

    private var header: some View {
        let current = forecast?.payload.current
        let daily = forecast?.payload.daily
        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.custom("HelveticaNeue-Bold", fixedSize: 22 * scale))
                    .lineLimit(1)
                Text(verbatim: forecast == nil ? "" : SettingService.formattedTime(.now, timeZone: timeZone))
                    .font(.custom("HelveticaNeue", fixedSize: 13 * scale))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                degrees(current?.temperature, size: 64 * scale, weight: "HelveticaNeue-Light")
                if let daily, daily.time.indices.contains(selectedDay) {
                    Text("H: \(rounded(daily.temperature_2m_max?[safe: selectedDay])) L: \(rounded(daily.temperature_2m_min?[safe: selectedDay]))")
                        .font(.custom("HelveticaNeue-Bold", fixedSize: 13 * scale))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.top, 58 * scale)
        .padding(.bottom, 6 * scale)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var heroArt: some View {
        if let forecast {
            ClassicHeroArt(
                weatherCode: forecast.currentWeatherCode,
                isDay: (forecast.payload.current?.is_day ?? 1) > 0,
                latitude: forecast.payload.latitude ?? 0,
                width: 288 * scale
            )
            .offset(y: -Self.heroOverhang * scale)
        }
    }

    // MARK: - Hourly strip

    private var hourlyStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(hours, id: \.time) { hour in
                    VStack(spacing: 4 * scale) {
                        Text(HourlyFormatting.hourString(timestamp: hour.time, timeZone: timeZone))
                            .font(.custom("HelveticaNeue-Bold", fixedSize: 11 * scale))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        miniArt(code: hour.code, isDay: hour.isDay > 0)
                        degrees(hour.temperature, size: 18 * scale, weight: "HelveticaNeue-Light")
                    }
                    .frame(width: 50 * scale)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 6 * scale)
        }
        .scrollIndicators(.hidden)
        .frame(height: 80 * scale)
    }

    private struct Hour {
        let time: Double
        let temperature: Double?
        let code: Double
        let isDay: Double
    }

    /// The selected day's hours; today starts at the current hour.
    private var hours: [Hour] {
        guard let hourly = forecast?.payload.hourly,
              let dayStart = forecast?.payload.daily?.time[safe: selectedDay]
        else { return [] }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let day = Date(timeIntervalSince1970: dayStart)
        let earliest = Date.now.timeIntervalSince1970 - 3600
        var result: [Hour] = []
        for (index, time) in hourly.time.enumerated() {
            guard time >= earliest, calendar.isDate(Date(timeIntervalSince1970: time), inSameDayAs: day) else { continue }
            result.append(Hour(
                time: time,
                temperature: hourly.temperature_2m?[safe: index],
                code: hourly.weathercode?[safe: index] ?? 0,
                isDay: hourly.is_day?[safe: index] ?? 1
            ))
        }
        return result
    }

    // MARK: - Day rows

    private var dayRows: some View {
        let daily = forecast?.payload.daily
        let count = daily?.time.count ?? 0
        return VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    selectedDay = index
                } label: {
                    dayRow(index: index, daily: daily)
                }
                .buttonStyle(.plain)
                .background(index == selectedDay ? Color.white.opacity(0.08) : .clear)
                if index < count - 1 { separator }
            }
        }
    }

    private func dayRow(index: Int, daily: Components.Schemas.DailyResponse?) -> some View {
        let date = Date(timeIntervalSince1970: daily?.time[safe: index] ?? 0)
        let weekday = SettingService.formattedWeekday(date, timeZone: timeZone)
        let high = daily?.temperature_2m_max?[safe: index]
        let low = daily?.temperature_2m_min?[safe: index]
        let code = daily?.weathercode?[safe: index] ?? 0
        return HStack(spacing: 0) {
            Text(weekday)
                .font(.custom("HelveticaNeue-Medium", fixedSize: 17 * scale))
                .lineLimit(1)
            Spacer()
            degrees(high, size: 22 * scale, weight: "HelveticaNeue-Light")
            degrees(low, size: 22 * scale, weight: "HelveticaNeue-Light")
                .foregroundStyle(Self.lowTemperatureColor)
                .frame(width: 48 * scale, alignment: .trailing)
        }
        .overlay {
            miniArt(code: code, isDay: true)
        }
        .padding(.horizontal, 14 * scale)
        .frame(height: 38 * scale)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(weekday), \(rounded(high)) bis \(rounded(low))"))
        .accessibilityAddTraits(index == selectedDay ? .isSelected : [])
    }

    /// The hero composition shrunk to row size.
    private func miniArt(code: Double, isDay: Bool) -> some View {
        ClassicHeroArt(
            weatherCode: code,
            isDay: isDay,
            latitude: forecast?.payload.latitude ?? 0,
            width: 76 * scale,
            cloudScale: 0.5
        )
        .clipped()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: onMap) {
                Image(systemName: "map.circle.fill")
                    .font(.system(size: 18 * scale))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel(Text("Karte"))
            Spacer()
            if let updatedAt {
                Text("Aktualisiert").bold() + Text(verbatim: " \(updatedAt.formatted(date: .numeric, time: .shortened))")
            }
            Spacer()
            Button(action: onInfo) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18 * scale))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel(Text("Orte verwalten"))
        }
        .font(.custom("HelveticaNeue", fixedSize: 12 * scale))
        .padding(.horizontal, 12 * scale)
        .frame(height: 26 * scale)
        .background(Color.black.opacity(0.25))
    }

    // MARK: - Style

    private static let lowTemperatureColor = Color(red: 0.58, green: 0.68, blue: 0.86)

    private var cardFill: some View {
        ZStack {
            Color(red: 0.12, green: 0.2, blue: 0.38)
            if let sky = forecast?.sky {
                AtmosphereSampler.skyGradient(snapshot: sky)
            }
            // The sky reads too bright for white type; iOS 6's card was deep navy.
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var cardShine: some View {
        RoundedRectangle(cornerRadius: 10 * scale)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.15)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            )
    }

    private var separator: some View {
        VStack(spacing: 0) {
            Color.black.opacity(0.6).frame(height: 1)
            Color.white.opacity(0.14).frame(height: 1)
        }
    }

    /// "21°" with the degree sign small and raised, like the original.
    private func degrees(_ value: Double?, size: CGFloat, weight: String) -> Text {
        guard let value else { return Text(verbatim: "–").font(.custom(weight, fixedSize: size)) }
        return Text(verbatim: "\(Int(value.rounded()))").font(.custom(weight, fixedSize: size))
            + Text(verbatim: "°").font(.custom(weight, fixedSize: size * 0.55)).baselineOffset(size * 0.45)
    }

    private func rounded(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "–"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
