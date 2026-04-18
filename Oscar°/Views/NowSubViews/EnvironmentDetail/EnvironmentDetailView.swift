import SwiftUI

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
            aqiComponentSnapshot(
                id: "pm25",
                label: "PM2.5",
                value: currentValue(from: weather.air.hourly?.european_aqi_pm2_5) ?? 0,
                accentColor: .blue,
                explanationBodyKey: "PM2.5 entsteht vor allem durch Verkehr, Holzfeuer und Industrie. Die feinen Partikel dringen tief in die Lunge ein und belasten Atemwege und Herz-Kreislauf-System."
            ),
            aqiComponentSnapshot(
                id: "pm10",
                label: "PM10",
                value: currentValue(from: weather.air.hourly?.european_aqi_pm10) ?? 0,
                accentColor: .cyan,
                explanationBodyKey: "PM10 stammt oft aus Straßenstaub, Baustellen und Landwirtschaft. Die Partikel reizen Augen und Atemwege und können Beschwerden bei empfindlichen Personen verstärken."
            ),
            aqiComponentSnapshot(
                id: "no2",
                label: "NO₂",
                value: currentValue(from: weather.air.hourly?.european_aqi_no2) ?? 0,
                accentColor: .orange,
                explanationBodyKey: "Stickstoffdioxid entsteht vor allem bei Verbrennungsprozessen im Straßenverkehr und in Heizungen. Es reizt die Atemwege und kann Asthma sowie andere Lungenerkrankungen verschlimmern."
            ),
            aqiComponentSnapshot(
                id: "o3",
                label: "O₃",
                value: currentValue(from: weather.air.hourly?.european_aqi_o3) ?? 0,
                accentColor: .green,
                explanationBodyKey: "Bodennahes Ozon bildet sich bei starker Sonneneinstrahlung aus Abgasen. Es kann Husten, Reizungen und eine verringerte Lungenfunktion auslösen."
            ),
            aqiComponentSnapshot(
                id: "so2",
                label: "SO₂",
                value: currentValue(from: weather.air.hourly?.european_aqi_so2) ?? 0,
                accentColor: .yellow,
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

    private var currentPollen: [PollenSnapshot] {
        [
            pollenSnapshot(type: .alder, label: String(localized: "Erle"), values: weather.air.hourly?.alder_pollen, accentColor: .pink),
            pollenSnapshot(type: .birch, label: String(localized: "Birke"), values: weather.air.hourly?.birch_pollen, accentColor: .teal),
            pollenSnapshot(type: .grass, label: String(localized: "Gräser"), values: weather.air.hourly?.grass_pollen, accentColor: .green),
            pollenSnapshot(type: .mugwort, label: String(localized: "Beifuß"), values: weather.air.hourly?.mugwort_pollen, accentColor: .indigo),
            pollenSnapshot(type: .ragweed, label: String(localized: "Ambrosia"), values: weather.air.hourly?.ragweed_pollen, accentColor: .brown),
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
        dominantPollen?.color ?? .green
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                EnvironmentDetailSegmentedControl(selectedSection: $selectedSection)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedSection {
                        case .aqi:
                            EnvironmentAirQualitySectionView(
                                currentAQI: currentAQI,
                                currentAQIBadge: currentAQI.map(aqiStatusKey(for:)) ?? "Keine Daten",
                                currentAQIColor: currentAQIColor,
                                aqiComponents: aqiComponents,
                                mainPollutant: mainPollutant,
                                time: time,
                                aqi: weather.air.hourly?.european_aqi ?? [],
                                pm25: weather.air.hourly?.european_aqi_pm2_5 ?? [],
                                pm10: weather.air.hourly?.european_aqi_pm10 ?? [],
                                no2: weather.air.hourly?.european_aqi_no2 ?? [],
                                o3: weather.air.hourly?.european_aqi_o3 ?? [],
                                so2: weather.air.hourly?.european_aqi_so2 ?? [],
                                maxTimeRange: maxTimeRange,
                                referenceDate: referenceDate,
                                chartScrollPosition: $chartScrollPosition
                            )
                        case .uv:
                            EnvironmentUVSectionView(
                                currentUV: currentUV,
                                currentUVBadge: currentUV.map(uvStatusKey(for:)) ?? "Keine Daten",
                                currentUVColor: currentUVColor,
                                riskTitle: currentUV.map(uvRiskTitleKey(for:)) ?? "Keine Daten",
                                riskBody: currentUV.map(uvRiskBodyKey(for:)) ?? "Für die aktuelle Stunde liegen keine UV-Daten vor.",
                                uvIndex: weather.air.hourly?.uv_index ?? [],
                                time: time,
                                maxTimeRange: maxTimeRange,
                                referenceDate: referenceDate,
                                chartScrollPosition: $chartScrollPosition
                            )
                        case .pollen:
                            EnvironmentPollenSectionView(
                                currentPollen: currentPollen,
                                dominantPollen: dominantPollen,
                                dominantPollenSeverityColor: dominantPollenSeverityColor,
                                time: time,
                                alder: weather.air.hourly?.alder_pollen ?? [],
                                birch: weather.air.hourly?.birch_pollen ?? [],
                                grass: weather.air.hourly?.grass_pollen ?? [],
                                mugwort: weather.air.hourly?.mugwort_pollen ?? [],
                                ragweed: weather.air.hourly?.ragweed_pollen ?? [],
                                maxTimeRange: maxTimeRange,
                                referenceDate: referenceDate,
                                chartScrollPosition: $chartScrollPosition
                            )
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

    private func aqiComponentSnapshot(
        id: String,
        label: String,
        value: Double,
        accentColor: Color,
        explanationBodyKey: String
    ) -> AQIComponentSnapshot {
        AQIComponentSnapshot(
            id: id,
            label: label,
            value: value,
            accentColor: accentColor,
            status: aqiStatusKey(for: value),
            statusColor: EnvironmentMetric.forAQI(id: id, label: label, value: value).color,
            explanationBodyKey: explanationBodyKey
        )
    }

    private func pollenSnapshot(type: PollenType, label: String, values: [Double?]?, accentColor: Color) -> PollenSnapshot? {
        guard let value = currentValue(from: values) else { return nil }
        let tier = type.tier(for: value)

        return PollenSnapshot(
            id: label,
            label: label,
            value: value,
            tier: tier,
            tierLabel: pollenTierKey(tier),
            color: EnvironmentMetric.forPollen(type: type, label: label, value: value)?.color ?? accentColor
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
}
