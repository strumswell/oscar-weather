import SwiftUI

struct HourlyDetailView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(\.dismiss) private var dismiss
    private let settingsService = SettingService.shared

    @State private var chartScrollSynchronizer = ChartScrollSynchronizer()
    @State private var chartTimelineVersion = 0
    @State private var dismissalFeedback = false
    @State private var selectedSection: HourlyDetailSection = .atmosphere

    var time: [Double] {
        weather.forecast.hourly?.time ?? []
    }

    private var maxTimeRange: ClosedRange<Date> {
        guard let start = time.first, let end = time.last else {
            return Date.now...Date.now.addingTimeInterval(86_400)
        }

        return Date(timeIntervalSince1970: start)...Date(timeIntervalSince1970: end)
    }

    var currentIndex: Int? {
        guard !time.isEmpty else { return nil }

        let now = Date.now.timeIntervalSince1970
        return time.firstIndex(where: { $0 >= now }) ?? time.indices.last
    }

    var referenceDate: Date {
        guard let currentIndex else { return Date.now }
        return Date(timeIntervalSince1970: time[currentIndex])
    }

    var windSpeedUnit: WindSpeedUnit {
        WindSpeedUnit(settingValue: settingsService.windSpeedUnit)
    }

    private var initialChartScrollPosition: Date {
        let paddedDate = referenceDate.addingTimeInterval(-21_600)

        if paddedDate < maxTimeRange.lowerBound {
            return maxTimeRange.lowerBound
        }
        if paddedDate > maxTimeRange.upperBound {
            return maxTimeRange.upperBound
        }
        return paddedDate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HourlyDetailSegmentedControl(selectedSection: $selectedSection)

                if time.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ContentUnavailableView(
                                "Keine stündlichen Daten",
                                systemImage: "clock.badge.questionmark",
                                description: Text("Für diesen Standort liegen aktuell keine stündlichen Details vor.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                        }
                        .padding()
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                } else {
                    TabView(selection: $selectedSection) {
                        ForEach(HourlyDetailSection.allCases) { section in
                            sectionPage(for: section)
                                .tag(section)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .navigationTitle("Stündliche Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: finish)
                }
            }
            .sensoryFeedback(.success, trigger: dismissalFeedback)
            .onChange(of: time) { _, _ in
                chartScrollSynchronizer.reset()
                chartTimelineVersion &+= 1
            }
        }
    }

    @ViewBuilder
    private func sectionPage(for section: HourlyDetailSection) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                sectionContent(for: section)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private func sectionContent(for section: HourlyDetailSection) -> some View {
        switch section {
        case .meteogram:
            meteogramSection
        case .atmosphere:
            temperatureSection
            precipitationSection
            humiditySection
        case .wind:
            windSection
            pressureSection
            if windSpeedUnit.usesBeaufortDisplay {
                BeaufortScaleInfoCard()
            }
        case .ground:
            soilTemperatureSection
            soilMoistureSection
            evapotranspirationSection
        }
    }

    private var meteogramSection: some View {
        // Single chart with its own scroll/zoom state — deliberately not part of
        // the cross-chart scroll synchronizer.
        MeteogramPage(
            input: meteogramInput,
            initialScrollPosition: initialChartScrollPosition
        )
        .id(chartTimelineVersion)
    }

    private var meteogramInput: MeteogramModel.Input {
        let hourly = weather.forecast.hourly
        let units = weather.forecast.hourly_units
        let probability: [Double] = (hourly?.precipitation_probability ?? []).map { $0 ?? 0 }

        return MeteogramModel.Input(
            time: time,
            temperature: hourly?.temperature_2m ?? [],
            precipitation: hourly?.precipitation ?? [],
            snowfall: hourly?.snowfall ?? [],
            precipitationProbability: probability,
            cloudcoverTotal: hourly?.cloudcover ?? [],
            cloudcoverLow: hourly?.cloudcover_low ?? [],
            cloudcoverMid: hourly?.cloudcover_mid ?? [],
            cloudcoverHigh: hourly?.cloudcover_high ?? [],
            windspeed: displayedWindSpeeds(hourly?.windspeed_10m ?? []),
            winddirection: hourly?.winddirection_10m ?? [],
            windgusts: displayedWindSpeeds(hourly?.windgusts_10m ?? []),
            pressure: hourly?.pressure_msl ?? [],
            weathercode: hourly?.weathercode ?? [],
            isDay: hourly?.is_day ?? [],
            temperatureUnit: units?.temperature_2m ?? "°C",
            precipitationUnit: units?.precipitation ?? "mm",
            pressureUnit: "hPa",
            windSpeedUnit: windSpeedUnit,
            referenceDate: referenceDate
        )
    }

    private var temperatureSection: some View {
        let temperature = weather.forecast.hourly?.temperature_2m ?? []
        let apparentTemperature = weather.forecast.hourly?.apparent_temperature ?? []
        let unit = weather.forecast.hourly_units?.temperature_2m ?? "°C"
        let currentTemperature = currentValue(from: temperature)
        let currentApparentTemperature = currentValue(from: apparentTemperature)

        return HourlyDetailChartCard(
            title: "Temperatur",
            value: formatted(currentTemperature, decimals: 1, unit: unit),
            badge: apparentTemperatureBadge(for: currentApparentTemperature, unit: unit),
            color: .orange,
            subtitle: "Lufttemperatur und gefühlte Temperatur"
        ) {
            TemperatureChart(
                temperature: temperature,
                apparentTemperature: apparentTemperature,
                time: time,
                unit: unit,
                maxTimeRange: maxTimeRange,
                referenceDate: referenceDate
            )
            .synchronizedChartScroll(
                initialX: initialChartScrollPosition,
                using: chartScrollSynchronizer
            )
            .id(chartTimelineVersion)
        }
    }

    private var precipitationSection: some View {
        let precipitation = weather.forecast.hourly?.precipitation ?? []
        let snowfall = weather.forecast.hourly?.snowfall ?? []
        let unit = weather.forecast.hourly_units?.precipitation ?? "mm"
        let currentPrecipitation = currentValue(from: precipitation)
        let currentSnowfall = currentValue(from: snowfall)
        let color: Color = (currentSnowfall ?? 0) > 0 ? .cyan : .blue

        return HourlyDetailChartCard(
            title: "Niederschlag",
            value: formatted(currentPrecipitation, decimals: 1, unit: unit),
            badge: precipitationBadge(precipitation: currentPrecipitation, snowfall: currentSnowfall),
            color: color,
            subtitle: "Regen und Schnee pro Stunde"
        ) {
            PrecipitationChart(
                precipitation: precipitation,
                snowfall: snowfall,
                time: time,
                unit: unit,
                maxTimeRange: maxTimeRange,
                referenceDate: referenceDate
            )
            .synchronizedChartScroll(
                initialX: initialChartScrollPosition,
                using: chartScrollSynchronizer
            )
            .id(chartTimelineVersion)
        }
    }

    private var humiditySection: some View {
        let humidity = weather.forecast.hourly?.relativehumidity_2m ?? []
        let currentHumidity = currentValue(from: humidity)

        return HourlyDetailChartCard(
            title: "Luftfeuchtigkeit",
            value: formatted(currentHumidity, decimals: 0, unit: "%"),
            badge: humidityBadge(for: currentHumidity),
            color: humidityColor(for: currentHumidity),
            subtitle: "Relative Luftfeuchtigkeit"
        ) {
            HumidityChart(
                humidity: humidity,
                time: time,
                unit: "%",
                maxTimeRange: maxTimeRange,
                referenceDate: referenceDate
            )
            .synchronizedChartScroll(
                initialX: initialChartScrollPosition,
                using: chartScrollSynchronizer
            )
            .id(chartTimelineVersion)
        }
    }

    private var windSection: some View {
        let rawWindspeed10m = weather.forecast.hourly?.windspeed_10m ?? []
        let rawWindspeed80m = weather.forecast.hourly?.windspeed_80m ?? []
        let rawWindspeed120m = weather.forecast.hourly?.windspeed_120m ?? []
        let rawWindspeed180m = weather.forecast.hourly?.windspeed_180m ?? []
        let windspeed10m = displayedWindSpeeds(rawWindspeed10m)
        let windspeed80m = displayedWindSpeeds(rawWindspeed80m)
        let windspeed120m = displayedWindSpeeds(rawWindspeed120m)
        let windspeed180m = displayedWindSpeeds(rawWindspeed180m)
        let winddirection10m = weather.forecast.hourly?.winddirection_10m ?? []
        let unit = windSpeedUnit.usesBeaufortDisplay ? windSpeedUnit.displayUnit : weather.forecast.hourly_units?.windspeed_10m ?? "km/h"
        let currentDirection = currentValue(from: winddirection10m)

        return VStack(alignment: .leading, spacing: 16) {
            HourlyDetailChartCard(
                title: "Wind",
                value: WindSpeedFormatter.string(currentValue(from: windspeed10m), unit: unit),
                badge: currentDirection.map { LocalizedStringKey(windDirectionName(for: $0)) } ?? "Keine Daten",
                color: .teal,
                subtitle: "Windgeschwindigkeit in mehreren Höhen"
            ) {
                WindChart(
                    windspeed10m: windspeed10m,
                    windspeed80m: windspeed80m,
                    windspeed120m: windspeed120m,
                    windspeed180m: windspeed180m,
                    winddirection10m: winddirection10m,
                    time: time,
                    unit: unit,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .synchronizedChartScroll(
                    initialX: initialChartScrollPosition,
                    using: chartScrollSynchronizer
                )
                .id(chartTimelineVersion)
            }
        }
    }

    private var pressureSection: some View {
        let pressure = weather.forecast.hourly?.pressure_msl ?? []
        let currentPressure = currentValue(from: pressure)

        return VStack(alignment: .leading, spacing: 16) {
            HourlyDetailChartCard(
                title: "Luftdruck",
                value: formatted(currentPressure, decimals: 0, unit: "hPa"),
                badge: pressureBadge(for: pressure),
                color: .purple,
                subtitle: "Meeresspiegel-Luftdruck"
            ) {
                PressureChart(
                    pressure: pressure,
                    time: time,
                    unit: "hPa",
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .synchronizedChartScroll(
                    initialX: initialChartScrollPosition,
                    using: chartScrollSynchronizer
                )
                .id(chartTimelineVersion)
            }

            HourlyDetailInfoCard(
                title: "Einordnung",
                message: "Sinkender Luftdruck deutet auf schlechtes Wetter oder Stürme hin, steigender Luftdruck auf gutes Wetter oder Hochdruckgebiete."
            )
        }
    }

    private var soilTemperatureSection: some View {
        let soilTemp0cm = weather.forecast.hourly?.soil_temperature_0cm ?? []
        let soilTemp6cm = weather.forecast.hourly?.soil_temperature_6cm ?? []
        let soilTemp18cm = weather.forecast.hourly?.soil_temperature_18cm ?? []
        let soilTemp54cm = weather.forecast.hourly?.soil_temperature_54cm ?? []
        let unit = weather.forecast.hourly_units?.soil_temperature_0cm ?? "°C"

        return HourlyDetailChartCard(
            title: "Bodentemperatur",
            value: formatted(currentValue(from: soilTemp0cm), decimals: 1, unit: unit),
            color: .brown,
            subtitle: "Temperatur in mehreren Bodentiefen"
        ) {
            SoilTemperatureChart(
                soilTemp0cm: soilTemp0cm,
                soilTemp6cm: soilTemp6cm,
                soilTemp18cm: soilTemp18cm,
                soilTemp54cm: soilTemp54cm,
                time: time,
                unit: unit,
                maxTimeRange: maxTimeRange,
                referenceDate: referenceDate
            )
            .synchronizedChartScroll(
                initialX: initialChartScrollPosition,
                using: chartScrollSynchronizer
            )
            .id(chartTimelineVersion)
        }
    }

    private var soilMoistureSection: some View {
        let soilMoisture0_1cm = weather.forecast.hourly?.soil_moisture_0_1cm ?? []
        let soilMoisture1_3cm = weather.forecast.hourly?.soil_moisture_1_3cm ?? []
        let soilMoisture3_9cm = weather.forecast.hourly?.soil_moisture_3_9cm ?? []
        let soilMoisture9_27cm = weather.forecast.hourly?.soil_moisture_9_27cm ?? []
        let soilMoisture27_81cm = weather.forecast.hourly?.soil_moisture_27_81cm ?? []
        let unit = weather.forecast.hourly_units?.soil_moisture_0_1cm ?? "m³/m³"

        return HourlyDetailChartCard(
            title: "Bodenwassergehalt",
            value: formatted(currentValue(from: soilMoisture0_1cm), decimals: 2, unit: unit),
            color: .brown,
            subtitle: "Volumetrischer Wassergehalt je Bodentiefe"
        ) {
            SoilMoistureChart(
                soilMoisture0_1cm: soilMoisture0_1cm,
                soilMoisture1_3cm: soilMoisture1_3cm,
                soilMoisture3_9cm: soilMoisture3_9cm,
                soilMoisture9_27cm: soilMoisture9_27cm,
                soilMoisture27_81cm: soilMoisture27_81cm,
                time: time,
                unit: unit,
                maxTimeRange: maxTimeRange,
                referenceDate: referenceDate
            )
            .synchronizedChartScroll(
                initialX: initialChartScrollPosition,
                using: chartScrollSynchronizer
            )
            .id(chartTimelineVersion)
        }
    }

    private var evapotranspirationSection: some View {
        let et0 = weather.forecast.hourly?.et0_fao_evapotranspiration ?? []
        let unit = weather.forecast.hourly_units?.et0_fao_evapotranspiration ?? "mm"

        return VStack(alignment: .leading, spacing: 16) {
            HourlyDetailChartCard(
                title: "Referenz-Evapotranspiration",
                value: formatted(currentValue(from: et0), decimals: 2, unit: unit),
                color: .blue,
                subtitle: "Wasserverlust einer Referenzfläche"
            ) {
                ET0EvapotranspirationChart(
                    et0: et0,
                    time: time,
                    unit: unit,
                    maxTimeRange: maxTimeRange,
                    referenceDate: referenceDate
                )
                .synchronizedChartScroll(
                    initialX: initialChartScrollPosition,
                    using: chartScrollSynchronizer
                )
                .id(chartTimelineVersion)
            }

            HourlyDetailInfoCard(
                title: "Einordnung",
                message: evapotranspirationExplanation(for: et0, unit: unit)
            )
        }
    }

    private func finish() {
        dismissalFeedback.toggle()
        dismiss()
    }
}
