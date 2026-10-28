import SwiftUI

extension HourlyTimelineModel {
    func buildLayout(for lens: HourlyLens, units: Units) -> HourlyLensLayout {
        let temperatureSymbol = units.temperature.symbol
        let temperatureFormat: (Double) -> String = { "\(Int($0.rounded()))\(temperatureSymbol)" }
        let temperatures = { (values: [Double]) in values.map(units.temperature.value(fromCelsius:)) }
        let percentFormat: (Double) -> String = { "\(Int($0.rounded()))%" }

        switch lens {
        case .overview:
            let temperature = temperatures(temperature)
            let apparentTemperature = temperatures(apparentTemperature)
            return HourlyLensLayout(
                lines: [line(apparentTemperature, .red, width: 3.5,
                             label: String(localized: "Gefühlt")),
                        line(temperature, .orange, label: String(localized: "Temperatur"))],
                domain: paddedDomain([temperature, apparentTemperature]),
                showsBars: true,
                barsAlpha: 0.75,
                extremes: extremeMarks(for: temperature),
                extremeFormat: temperatureFormat,
                primaryColor: .orange,
                barsLabel: String(localized: "Regen")
            )
        case .wind:
            let displayed = { (values: [Double]) in values.map(units.windValue) }
            let heights = [windspeed180, windspeed120, windspeed80].map(displayed)
            let heightColors: [Color] = [.teal.mix(with: .black, by: 0.55),
                                         .teal.mix(with: .black, by: 0.4),
                                         .teal.mix(with: .black, by: 0.25)]
            let heightLabels = ["180 m", "120 m", "80 m"]
            let speeds = displayed(windspeed)
            let windUnit = units.wind.symbol
            return HourlyLensLayout(
                lines: zip(zip(heights, heightColors), heightLabels).map { pair, label in
                    line(pair.0, pair.1, width: 2.5, label: label)
                } + [line(speeds, .teal, label: "10 m")],
                domain: paddedDomain(heights + [speeds], from: 0),
                showsBars: false,
                barsAlpha: 0,
                extremes: [],
                extremeFormat: { "\(Int($0.rounded())) \(windUnit)" },
                primaryColor: .teal,
                showsDirectionArrows: true
            )
        case .pressure:
            let pressure = pressure.map(units.pressure.value(fromHectopascals:))
            let pressureUnit = units.pressure
            return HourlyLensLayout(
                lines: [line(pressure, .purple)],
                domain: paddedDomain([pressure], minimumPad: pressureUnit.value(fromHectopascals: 2)),
                showsBars: false,
                barsAlpha: 0,
                extremes: extremeMarks(for: pressure),
                extremeFormat: { "\($0.formatted(.number.grouping(.never).precision(.fractionLength(pressureUnit.fractionDigits)))) \(pressureUnit.symbol)" },
                primaryColor: .purple
            )
        case .humidity:
            return HourlyLensLayout(
                lines: [line(humidity, .mint)],
                domain: 0...105,
                showsBars: false,
                barsAlpha: 0,
                extremes: extremeMarks(for: humidity),
                extremeFormat: percentFormat,
                primaryColor: .mint
            )
        case .clouds:
            return HourlyLensLayout(
                lines: [],
                domain: 0...1,
                showsBars: false,
                barsAlpha: 0,
                extremes: [],
                extremeFormat: percentFormat,
                primaryColor: .hourlyCloud,
                bands: [.init(values: cloudHigh, centerFraction: 0.30, label: String(localized: "Hohe Wolken")),
                        .init(values: cloudMid, centerFraction: 0.53, label: String(localized: "Mittlere Wolken")),
                        .init(values: cloudLow, centerFraction: 0.76, label: String(localized: "Tiefe Wolken"))]
            )
        case .soilTemperature:
            let soilTemperature0 = temperatures(soilTemperature0)
            let soilTemperature6 = temperatures(soilTemperature6)
            let soilTemperature18 = temperatures(soilTemperature18)
            let soilTemperature54 = temperatures(soilTemperature54)
            return HourlyLensLayout(
                lines: [line(soilTemperature54, .brown.mix(with: .black, by: 0.55), width: 2.5, label: "54 cm"),
                        line(soilTemperature18, .brown.mix(with: .black, by: 0.4), width: 2.8, label: "18 cm"),
                        line(soilTemperature6, .brown.mix(with: .black, by: 0.25), width: 3.1, label: "6 cm"),
                        line(soilTemperature0, .brown, label: "0 cm")],
                domain: paddedDomain([soilTemperature0, soilTemperature6, soilTemperature18, soilTemperature54]),
                showsBars: false,
                barsAlpha: 0,
                extremes: [],
                extremeFormat: temperatureFormat,
                primaryColor: .brown
            )
        case .soilMoisture:
            let depths = soilMoisture
            let depthColors: [Color] = [.blue.mix(with: .black, by: 0.6),
                                        .blue.mix(with: .black, by: 0.48),
                                        .blue.mix(with: .black, by: 0.35),
                                        .blue.mix(with: .black, by: 0.2)]
            let depthLabels = ["27–81 cm", "9–27 cm", "3–9 cm", "1–3 cm"]
            let secondaries = zip(zip(depths.dropLast(), depthColors), depthLabels).map { pair, label in
                line(pair.0, pair.1, width: 2.5, label: label)
            }
            return HourlyLensLayout(
                lines: secondaries + [line(depths.last ?? [], .blue, label: "0–1 cm")],
                domain: paddedDomain(depths, minimumPad: 0.02),
                showsBars: false,
                barsAlpha: 0,
                extremes: [],
                extremeFormat: { "\($0.formatted(.number.precision(.fractionLength(2)))) m³⁄m³" },
                primaryColor: .blue
            )
        case .evapotranspiration:
            let precipitationUnit = units.precipitation
            let et0 = et0.map(precipitationUnit.value(fromMillimeters:))
            let floor = precipitationUnit.value(fromMillimeters: 0.05)
            return HourlyLensLayout(
                lines: [line(et0, .hourlyRain)],
                domain: paddedDomain([et0], from: 0, minimumPad: floor),
                showsBars: false,
                barsAlpha: 0,
                extremes: extremeMarks(for: et0, highsOnly: true, atLeast: floor),
                extremeFormat: { "\($0.formatted(.number.precision(.fractionLength(precipitationUnit.fractionDigits + 1)))) \(precipitationUnit.symbol)" },
                primaryColor: .hourlyRain
            )
        }
    }

    private func line(
        _ values: [Double],
        _ color: Color,
        width: CGFloat = 4,
        label: String? = nil
    ) -> HourlyLensLayout.Line {
        HourlyLensLayout.Line(values: values, color: color, width: width, label: label)
    }

    private func paddedDomain(
        _ series: [[Double]],
        from lowerPin: Double? = nil,
        minimumPad: Double = 0.5
    ) -> ClosedRange<Double> {
        let all = series.flatMap { $0 }
        guard var low = all.min(), var high = all.max() else { return 0...1 }
        let pad = max((high - low) * 0.08, minimumPad)
        low = lowerPin ?? (low - pad)
        high += pad
        guard high > low else { return low...(low + 1) }
        return low...high
    }

    private func extremeMarks(
        for values: [Double],
        highsOnly: Bool = false,
        atLeast threshold: Double = -.infinity
    ) -> [ExtremeMark] {
        let marks = Self.dailyExtremes(times: times, values: values, timeZone: timeZone)
        guard highsOnly else { return marks }
        return marks.filter { $0.isHigh && $0.value >= threshold }
    }
}
