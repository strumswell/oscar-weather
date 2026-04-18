//
//  EnvironmentDetailView.swift
//  Oscar°
//

import SwiftUI

enum EnvironmentDetailSection: String, Hashable, Identifiable {
    case aqi
    case uv
    case pollen

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .aqi:
            "Luftqualität"
        case .uv:
            "UV-Index"
        case .pollen:
            "Pollen"
        }
    }
}

private struct AQIComponentSnapshot: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
    let explanationTitleKey: String
    let explanationBodyKey: String
}

private struct PollenSnapshot: Identifiable {
    let id: String
    let type: PollenType
    let label: String
    let value: Double
    let tier: PollenTier
    let color: Color
}

struct EnvironmentDetailView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: EnvironmentDetailSection
    @State private var chartScrollPosition = Date.now
    @State private var didSetInitialChartPosition = false

    init(scrollTo: EnvironmentDetailSection) {
        _selectedSection = State(initialValue: scrollTo)
    }

    private var time: [Double] {
        weather.air.hourly?.time ?? []
    }

    private var maxTimeRange: ClosedRange<Date> {
        guard let start = time.first, let end = time.last else {
            return Date.now...Date.now.addingTimeInterval(86_400)
        }

        return Date(timeIntervalSince1970: start)...Date(timeIntervalSince1970: end)
    }

    private var currentIndex: Int? {
        currentEnvironmentHourIndex(time: time)
    }

    private var referenceDate: Date {
        guard let currentIndex else { return Date.now }
        return Date(timeIntervalSince1970: time[currentIndex])
    }

    private var initialChartScrollPosition: Date {
        let paddedDate = referenceDate.addingTimeInterval(-36_000)
        if paddedDate < maxTimeRange.lowerBound {
            return maxTimeRange.lowerBound
        }
        if paddedDate > maxTimeRange.upperBound {
            return maxTimeRange.upperBound
        }
        return paddedDate
    }

    private var currentAQI: Double? {
        currentValue(from: weather.air.hourly?.european_aqi)
    }

    private var currentAQIColor: Color {
        EnvironmentMetric.forAQI(id: "aqi", label: "AQI", value: currentAQI).color
    }

    private var aqiComponents: [AQIComponentSnapshot] {
        [
            AQIComponentSnapshot(
                id: "pm25",
                label: "PM2.5",
                value: currentValue(from: weather.air.hourly?.european_aqi_pm2_5) ?? 0,
                color: .blue,
                explanationTitleKey: "PM2.5",
                explanationBodyKey: "PM2.5 entsteht vor allem durch Verkehr, Holzfeuer und Industrie. Die feinen Partikel dringen tief in die Lunge ein und belasten Atemwege und Herz-Kreislauf-System."
            ),
            AQIComponentSnapshot(
                id: "pm10",
                label: "PM10",
                value: currentValue(from: weather.air.hourly?.european_aqi_pm10) ?? 0,
                color: .cyan,
                explanationTitleKey: "PM10",
                explanationBodyKey: "PM10 stammt oft aus Straßenstaub, Baustellen und Landwirtschaft. Die Partikel reizen Augen und Atemwege und können Beschwerden bei empfindlichen Personen verstärken."
            ),
            AQIComponentSnapshot(
                id: "no2",
                label: "NO₂",
                value: currentValue(from: weather.air.hourly?.european_aqi_no2) ?? 0,
                color: .orange,
                explanationTitleKey: "NO₂",
                explanationBodyKey: "Stickstoffdioxid entsteht vor allem bei Verbrennungsprozessen im Straßenverkehr und in Heizungen. Es reizt die Atemwege und kann Asthma sowie andere Lungenerkrankungen verschlimmern."
            ),
            AQIComponentSnapshot(
                id: "o3",
                label: "O₃",
                value: currentValue(from: weather.air.hourly?.european_aqi_o3) ?? 0,
                color: .green,
                explanationTitleKey: "O₃",
                explanationBodyKey: "Bodennahes Ozon bildet sich bei starker Sonneneinstrahlung aus Abgasen. Es kann Husten, Reizungen und eine verringerte Lungenfunktion auslösen."
            ),
            AQIComponentSnapshot(
                id: "so2",
                label: "SO₂",
                value: currentValue(from: weather.air.hourly?.european_aqi_so2) ?? 0,
                color: .yellow,
                explanationTitleKey: "SO₂",
                explanationBodyKey: "Schwefeldioxid entsteht vor allem bei der Verbrennung schwefelhaltiger Brennstoffe in Industrie und Energieerzeugung. Es reizt die Atemwege und belastet besonders Menschen mit Asthma."
            ),
        ]
        .sorted { $0.value > $1.value }
    }

    private var mainPollutant: AQIComponentSnapshot? {
        aqiComponents.first(where: { $0.value > 0 })
    }

    private var currentUV: Double? {
        currentValue(from: weather.air.hourly?.uv_index)
    }

    private var currentUVColor: Color {
        EnvironmentMetric.forUV(value: currentUV).color
    }

    private var uvPeakToday: (value: Double, time: Date)? {
        let points = zip(time, weather.air.hourly?.uv_index ?? []).map { timestamp, value in
            (value: value, time: Date(timeIntervalSince1970: timestamp))
        }
        return points.max { $0.value < $1.value }
    }

    private var currentPollen: [PollenSnapshot] {
        [
            pollenSnapshot(type: .alder, label: String(localized: "Erle"), values: weather.air.hourly?.alder_pollen, color: .pink),
            pollenSnapshot(type: .birch, label: String(localized: "Birke"), values: weather.air.hourly?.birch_pollen, color: .teal),
            pollenSnapshot(type: .grass, label: String(localized: "Gräser"), values: weather.air.hourly?.grass_pollen, color: .green),
            pollenSnapshot(type: .mugwort, label: String(localized: "Beifuß"), values: weather.air.hourly?.mugwort_pollen, color: .indigo),
            pollenSnapshot(type: .ragweed, label: String(localized: "Ambrosia"), values: weather.air.hourly?.ragweed_pollen, color: .brown),
        ]
        .compactMap { $0 }
        .sorted {
            if $0.tier == $1.tier {
                return $0.value > $1.value
            }
            return $0.tier > $1.tier
        }
    }

    private var dominantPollen: PollenSnapshot? {
        currentPollen.first
    }

    private var dominantPollenSeverityColor: Color {
        guard let dominantPollen else { return .green }

        return EnvironmentMetric.forPollen(
            type: dominantPollen.type,
            label: dominantPollen.label,
            value: dominantPollen.value
        )?.color ?? .green
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Umweltdetails", selection: $selectedSection) {
                    Text(EnvironmentDetailSection.aqi.title).tag(EnvironmentDetailSection.aqi)
                    Text(EnvironmentDetailSection.uv.title).tag(EnvironmentDetailSection.uv)
                    Text(EnvironmentDetailSection.pollen.title).tag(EnvironmentDetailSection.pollen)
                }
                .pickerStyle(.segmented)
                .padding(6)
                .background(.thinMaterial, in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedSection {
                        case .aqi:
                            airQualityContent
                        case .uv:
                            uvContent
                        case .pollen:
                            pollenContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Umweltdetails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Fertig"), action: dismiss.callAsFunction)
                }
            }
            .onAppear {
                initializeChartPositionIfNeeded()
            }
            .onChange(of: time) { _, _ in
                initializeChartPositionIfNeeded(force: true)
            }
        }
    }

    private var airQualityContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard {
                headerBlock(
                    title: "Luftqualität",
                    value: currentAQI.map { String(Int($0)) } ?? "--",
                    badge: currentAQI.map(aqiStatusKey(for:)) ?? "Keine Daten",
                    color: currentAQIColor,
                    subtitle: nil
                )

                AQIChart(
                    aqi: weather.air.hourly?.european_aqi ?? [],
                    pm25: weather.air.hourly?.european_aqi_pm2_5 ?? [],
                    pm10: weather.air.hourly?.european_aqi_pm10 ?? [],
                    no2: weather.air.hourly?.european_aqi_no2 ?? [],
                    o3: weather.air.hourly?.european_aqi_o3 ?? [],
                    so2: weather.air.hourly?.european_aqi_so2 ?? [],
                    time: time,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .chartScrollPosition(x: $chartScrollPosition)
            }

            sectionCard {
                sectionTitle("Hauptschadstoff")

                if let mainPollutant {
                    Text(verbatim: mainPollutant.label)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(mainPollutant.color)

                    Text("Aktuell dominierender Schadstoff")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(LocalizedStringKey(mainPollutant.explanationBodyKey))
                        .font(.body)
                        .foregroundStyle(.primary)
                } else {
                    emptyContent(
                        title: "Keine Daten",
                        message: "Für die aktuelle Stunde liegen keine Luftqualitätsdaten vor."
                    )
                }
            }
            
            sectionCard {
                sectionTitle("Schadstoffe jetzt")

                ForEach(Array(aqiComponents.enumerated()), id: \.element.id) { index, component in
                    if index > 0 {
                        Divider().overlay(.white.opacity(0.08))
                    }

                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(LocalizedStringKey(aqiStatusKey(for: component.value)))
                                .fontWeight(.semibold)
                                .foregroundStyle(EnvironmentMetric.forAQI(
                                    id: component.id,
                                    label: component.label,
                                    value: component.value
                                ).color)
                        }
                    } label: {
                        Text(verbatim: component.label)
                    }
                }
            }
        }
    }

    private var uvContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionCard {
                headerBlock(
                    title: "UV-Index",
                    value: currentUV.map { String(format: "%.1f", $0) } ?? "--",
                    badge: currentUV.map(uvStatusKey(for:)) ?? "Keine Daten",
                    color: currentUVColor,
                    subtitle: nil
                )

                UVChart(
                    uvIndex: weather.air.hourly?.uv_index ?? [],
                    time: time,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .chartScrollPosition(x: $chartScrollPosition)
            }

            sectionCard {
                sectionTitle("Gesundheitsbewertung")

                Text(LocalizedStringKey(currentUV.map(uvRiskTitleKey(for:)) ?? "Keine Daten"))
                    .font(.headline)
                    .foregroundStyle(currentUVColor)

                Text(LocalizedStringKey(currentUV.map(uvRiskBodyKey(for:)) ?? "Für die aktuelle Stunde liegen keine UV-Daten vor."))
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    private var pollenContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if currentPollen.isEmpty {
                sectionCard {
                    emptyContent(
                        title: "Keine Pollendaten verfügbar",
                        message: "Für den aktuellen Zeitraum liegen keine Pollendaten vor."
                    )
                }
            } else {
                sectionCard {
                    headerBlock(
                        title: "Pollen",
                        value: dominantPollen?.label ?? "--",
                        badge: dominantPollen.map { pollenTierKey($0.tier) } ?? "Keine Daten",
                        color: dominantPollenSeverityColor,
                        subtitle: nil
                    )

                    PollenChart(
                        time: time,
                        alder: weather.air.hourly?.alder_pollen ?? [],
                        birch: weather.air.hourly?.birch_pollen ?? [],
                        grass: weather.air.hourly?.grass_pollen ?? [],
                        mugwort: weather.air.hourly?.mugwort_pollen ?? [],
                        ragweed: weather.air.hourly?.ragweed_pollen ?? [],
                        maxTimeRange: maxTimeRange,
                        referenceDate: referenceDate
                    )
                    .chartScrollPosition(x: $chartScrollPosition)
                }

                sectionCard {
                    sectionTitle("Aktuelle Werte")

                    ForEach(Array(currentPollen.enumerated()), id: \.element.id) { index, pollen in
                        if index > 0 {
                            Divider().overlay(.white.opacity(0.08))
                        }

                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(pollen.value))")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(
                                        EnvironmentMetric.forPollen(
                                            type: pollen.type,
                                            label: pollen.label,
                                            value: pollen.value
                                        )?.color ?? pollen.color
                                    )

                                Text("Pollen/m³")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: pollen.label)
                                Text(LocalizedStringKey(pollenTierKey(pollen.tier)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func initializeChartPositionIfNeeded(force: Bool = false) {
        guard !time.isEmpty else { return }
        guard force || !didSetInitialChartPosition else { return }

        chartScrollPosition = initialChartScrollPosition
        didSetInitialChartPosition = true
    }

    private func currentValue(from values: [Double]?) -> Double? {
        guard let currentIndex, let values, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    private func currentValue(from values: [Double?]?) -> Double? {
        guard let currentIndex, let values, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    private func pollenSnapshot(type: PollenType, label: String, values: [Double?]?, color: Color) -> PollenSnapshot? {
        guard let value = currentValue(from: values) else { return nil }

        return PollenSnapshot(
            id: label,
            type: type,
            label: label,
            value: value,
            tier: type.tier(for: value),
            color: color
        )
    }

    private func aqiStatusKey(for value: Double) -> String {
        switch value {
        case ..<20:
            "Gut"
        case ..<40:
            "Akzeptabel"
        case ..<60:
            "Mäßig"
        case ..<80:
            "Schlecht"
        case ..<100:
            "Sehr schlecht"
        default:
            "Extrem schlecht"
        }
    }

    private func uvStatusKey(for value: Double) -> String {
        switch value {
        case ..<3:
            "Gering"
        case ..<6:
            "Mittel"
        case ..<8:
            "Hoch"
        case ..<11:
            "Sehr Hoch"
        default:
            "Extrem"
        }
    }

    private func uvRiskTitleKey(for value: Double) -> String {
        switch value {
        case ..<3:
            "Geringe gesundheitliche Gefährdung"
        case ..<6:
            "Mittlere gesundheitliche Gefährdung, Schutzmaßnahmen sind erforderlich."
        case ..<8:
            "Hohe gesundheitliche Gefährdung, Schutzmaßnahmen sind erforderlich."
        case ..<11:
            "Sehr hohe gesundheitliche Gefährdung, Schutzmaßnahmen sind unbedingt erforderlich."
        default:
            "Extreme gesundheitliche Gefährdung, Besondere Schutzmaßnahmen sind ein Muss."
        }
    }

    private func uvRiskBodyKey(for value: Double) -> String {
        switch value {
        case ..<3:
            "Bei diesem UV-Wert besteht nur eine geringe gesundheitliche Gefährdung. Meist sind keine besonderen Schutzmaßnahmen erforderlich."
        case ..<6:
            "Hemd, Sonnencreme und Sonnenbrille schützen vor zu viel UV-Strahlung."
        case ..<8:
            "Die Weltgesundheitsorganisation (WHO) rät, mittags den Schatten zu suchen. In der Sonne werden Hemd, Sonnencreme, Sonnenbrille und Kopfbedeckung benötigt."
        case ..<11:
            "Die Weltgesundheitsorganisation (WHO) rät, zwischen 11 und 16 Uhr den Aufenthalt im Freien zu vermeiden, aber auch im Schatten gehören ein sonnendichtes Hemd, lange Hosen, Sonnencreme, Sonnenbrille und ein breitkrempiger Hut zum sonnengerechten Verhalten."
        default:
            "Die Weltgesundheitsorganisation (WHO) empfiehlt, zwischen 11 und 16 Uhr im Schutz eines Hauses zu bleiben und auch außerhalb dieser Zeit unbedingt Schatten zu suchen. Ein sonnendichtes Hemd, lange Hosen, Sonnencreme, Sonnenbrille und ein breitkrempiger Hut sind auch im Schatten unerlässlich."
        }
    }

    private func pollenTierKey(_ tier: PollenTier) -> String {
        switch tier {
        case .none:
            "Keine"
        case .low:
            "Gering"
        case .moderate:
            "Mäßig"
        case .high:
            "Hoch"
        case .veryHigh:
            "Sehr Hoch"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func headerBlock(
        title: LocalizedStringKey,
        value: String,
        badge: String,
        color: Color,
        subtitle: String?
    ) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: value)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(LocalizedStringKey(badge))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.18), in: .capsule)
                .foregroundStyle(color)
        }

        if let subtitle {
            Text(verbatim: subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func emptyContent(title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
