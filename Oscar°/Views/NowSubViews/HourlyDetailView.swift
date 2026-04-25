import SwiftUI

struct HourlyDetailView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(\.dismiss) private var dismiss

    @State private var chartScrollPosition = Date.now
    @State private var didSetInitialChartPosition = false
    @State private var dismissalFeedback = false
    @State private var selectedSection: HourlyDetailSection = .atmosphere

    private var time: [Double] {
        weather.forecast.hourly?.time ?? []
    }

    private var maxTimeRange: ClosedRange<Date> {
        guard let start = time.first, let end = time.last else {
            return Date.now...Date.now.addingTimeInterval(86_400)
        }

        return Date(timeIntervalSince1970: start)...Date(timeIntervalSince1970: end)
    }

    private var currentIndex: Int? {
        guard !time.isEmpty else { return nil }

        let now = Date.now.timeIntervalSince1970
        return time.firstIndex(where: { $0 >= now }) ?? time.indices.last
    }

    private var referenceDate: Date {
        guard let currentIndex else { return Date.now }
        return Date(timeIntervalSince1970: time[currentIndex])
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
                    Button(String(localized: "Fertig"), action: finish)
                }
            }
            .sensoryFeedback(.success, trigger: dismissalFeedback)
            .task {
                initializeChartPositionIfNeeded()
            }
            .onChange(of: time) { _, _ in
                initializeChartPositionIfNeeded(force: true)
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
        case .atmosphere:
            temperatureSection
            precipitationSection
            humiditySection
        case .wind:
            windSection
            pressureSection
        case .ground:
            soilTemperatureSection
            soilMoistureSection
            evapotranspirationSection
        }
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
            .chartScrollPosition(x: $chartScrollPosition)
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
            .chartScrollPosition(x: $chartScrollPosition)
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
            .chartScrollPosition(x: $chartScrollPosition)
        }
    }

    private var windSection: some View {
        let windspeed10m = weather.forecast.hourly?.windspeed_10m ?? []
        let windspeed80m = weather.forecast.hourly?.windspeed_80m ?? []
        let windspeed120m = weather.forecast.hourly?.windspeed_120m ?? []
        let windspeed180m = (weather.forecast.hourly?.windspeed_180m ?? []).map { $0 ?? 0 }
        let winddirection10m = weather.forecast.hourly?.winddirection_10m ?? []
        let unit = weather.forecast.hourly_units?.windspeed_10m ?? "km/h"
        let currentDirection = currentValue(from: winddirection10m)

        return HourlyDetailChartCard(
            title: "Wind",
            value: formatted(currentValue(from: windspeed10m), decimals: 1, unit: unit),
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
            .chartScrollPosition(x: $chartScrollPosition)
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
                .chartScrollPosition(x: $chartScrollPosition)
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
            .chartScrollPosition(x: $chartScrollPosition)
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
            .chartScrollPosition(x: $chartScrollPosition)
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
                .chartScrollPosition(x: $chartScrollPosition)
            }

            HourlyDetailInfoCard(
                title: "Einordnung",
                message: evapotranspirationExplanation(for: et0, unit: unit)
            )
        }
    }

    private func initializeChartPositionIfNeeded(force: Bool = false) {
        guard !time.isEmpty else { return }
        guard force || !didSetInitialChartPosition else { return }

        chartScrollPosition = initialChartScrollPosition
        didSetInitialChartPosition = true
    }

    private func currentValue(from values: [Double]) -> Double? {
        guard let currentIndex, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    private func currentValue(from values: [Double?]) -> Double? {
        guard let currentIndex, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    private func formatted(_ value: Double?, decimals: Int, unit: String) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(decimals)f %@", value, unit)
    }

    private func formatted(_ value: Double, decimals: Int, unit: String) -> String {
        String(format: "%.\(decimals)f %@", value, unit)
    }

    private func apparentTemperatureBadge(for apparentTemperature: Double?, unit: String) -> LocalizedStringKey {
        guard let apparentTemperature else { return "Keine Daten" }
        let value = formatted(apparentTemperature, decimals: 1, unit: unit)
        return "Gefühlt \(value)"
    }

    private func precipitationBadge(precipitation: Double?, snowfall: Double?) -> LocalizedStringKey {
        guard let precipitation else { return "Keine Daten" }
        if let snowfall, snowfall > 0 {
            return "Schnee"
        }
        return precipitation > 0 ? "Regen" : "Trocken"
    }

    private func humidityBadge(for humidity: Double?) -> LocalizedStringKey {
        guard let humidity else { return "Keine Daten" }

        switch humidity {
        case ..<35:
            return "Trocken"
        case ..<65:
            return "Angenehm"
        default:
            return "Feucht"
        }
    }

    private func humidityColor(for humidity: Double?) -> Color {
        guard let humidity else { return .secondary }

        switch humidity {
        case ..<35:
            return .orange
        case ..<65:
            return .green
        default:
            return .blue
        }
    }

    private func pressureBadge(for pressure: [Double]) -> LocalizedStringKey {
        guard let currentIndex, currentIndex < pressure.count else {
            return "Keine Daten"
        }

        let outlookIndex = min(currentIndex + 24, pressure.index(before: pressure.endIndex))
        guard outlookIndex > currentIndex else { return "Stabil" }

        let delta = pressure[outlookIndex] - pressure[currentIndex]
        if delta > 2 {
            return "Steigend"
        }
        if delta < -2 {
            return "Fallend"
        }
        return "Stabil"
    }

    private func evapotranspirationExplanation(for et0: [Double], unit: String) -> LocalizedStringKey {
        let total = evapotranspirationTotalForReferenceDay(from: et0)
        let formattedTotal = formatted(total, decimals: 1, unit: unit)
        let liters = String(format: "%.1f", total)

        if unit == "mm" {
            return "ET₀ beschreibt, wie viel Wasser eine gut versorgte Referenzfläche an die Luft abgibt. Für heute summieren sich die stündlichen Werte auf \(formattedTotal). Das entspricht ungefähr \(liters) Litern Wasser pro Quadratmeter."
        }

        return "ET₀ beschreibt, wie viel Wasser eine gut versorgte Referenzfläche an die Luft abgibt. Für heute summieren sich die stündlichen Werte auf \(formattedTotal). Bei Millimeter-Angaben entspricht 1 mm ungefähr 1 Liter Wasser pro Quadratmeter."
    }

    private func evapotranspirationTotalForReferenceDay(from et0: [Double]) -> Double {
        let calendar = Calendar.current

        return time.indices.reduce(0) { total, index in
            guard index < et0.count else { return total }
            let date = Date(timeIntervalSince1970: time[index])
            guard calendar.isDate(date, inSameDayAs: referenceDate) else { return total }
            return total + et0[index]
        }
    }

    private func windDirectionName(for degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)

        switch normalized {
        case 337.5..<360, 0..<22.5:
            return "N"
        case 22.5..<67.5:
            return "NO"
        case 67.5..<112.5:
            return "O"
        case 112.5..<157.5:
            return "SO"
        case 157.5..<202.5:
            return "S"
        case 202.5..<247.5:
            return "SW"
        case 247.5..<292.5:
            return "W"
        default:
            return "NW"
        }
    }

    private func finish() {
        dismissalFeedback.toggle()
        dismiss()
    }
}
