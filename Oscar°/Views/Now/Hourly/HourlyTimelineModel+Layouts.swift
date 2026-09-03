import SwiftUI

extension HourlyTimelineModel {
    func buildLayout(for lens: HourlyLens) -> HourlyLensLayout {
        // The format closures capture plain locals, not self: layouts live in
        // a cache on the model, so a self capture would cycle.
        let temperatureUnit = self.temperatureUnit
        let temperatureFormat: (Double) -> String = { "\(Int($0.rounded()))\(temperatureUnit)" }
        let percentFormat: (Double) -> String = { "\(Int($0.rounded()))%" }

        switch lens {
        case .overview:
            return HourlyLensLayout(
                lines: [line(apparentTemperature, .red, width: 3.5,
                             label: String(localized: "Gefühlt")),
                        line(temperature, .orange, label: String(localized: "Temperatur"))],
                domain: paddedDomain([temperature, apparentTemperature]),
                showsBars: true,
                barsAlpha: 0.75,
                fillsPrimary: false,
                extremes: extremeMarks(for: temperature),
                extremeFormat: temperatureFormat,
                primaryColor: .orange,
                barsLabel: String(localized: "Regen")
            )
        case .wind:
            let unit = WindSpeedUnit(settingValue: SettingService.shared.windSpeedUnit)
            let displayed: ([Double]) -> [Double] = unit.usesBeaufortDisplay
                ? BeaufortScale.convertedValues(fromKilometersPerHour:)
                : { $0 }
            // Highest altitude first: the readout box lists lines in reverse,
            // so its rows read 10 m upwards.
            let heights = [windspeed180, windspeed120, windspeed80].map(displayed)
            let heightColors: [Color] = [.teal.mix(with: .black, by: 0.55),
                                         .teal.mix(with: .black, by: 0.4),
                                         .teal.mix(with: .black, by: 0.25)]
            let heightLabels = ["180 m", "120 m", "80 m"]
            let speeds = displayed(windspeed)
            let windUnit = unit.usesBeaufortDisplay ? unit.displayUnit : windUnitString
            return HourlyLensLayout(
                lines: zip(zip(heights, heightColors), heightLabels).map { pair, label in
                    line(pair.0, pair.1, width: 2.5, label: label)
                } + [line(speeds, .teal, label: "10 m")],
                domain: paddedDomain(heights + [speeds], from: 0),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: [],
                extremeFormat: { "\(Int($0.rounded())) \(windUnit)" },
                primaryColor: .teal,
                showsDirectionArrows: true
            )
        case .pressure:
            return HourlyLensLayout(
                lines: [line(pressure, .purple)],
                domain: paddedDomain([pressure], minimumPad: 2),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: extremeMarks(for: pressure),
                extremeFormat: { "\(Int($0.rounded())) hPa" },
                primaryColor: .purple
            )
        case .humidity:
            return HourlyLensLayout(
                lines: [line(humidity, .mint)],
                domain: 0...105,
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
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
                fillsPrimary: false,
                extremes: [],
                extremeFormat: percentFormat,
                primaryColor: .hourlyCloud,
                bands: [.init(values: cloudHigh, centerFraction: 0.30, label: String(localized: "Hohe Wolken")),
                        .init(values: cloudMid, centerFraction: 0.53, label: String(localized: "Mittlere Wolken")),
                        .init(values: cloudLow, centerFraction: 0.76, label: String(localized: "Tiefe Wolken"))]
            )
        case .soilTemperature:
            return HourlyLensLayout(
                lines: [line(soilTemperature54, .brown.mix(with: .black, by: 0.55), width: 2.5, label: "54 cm"),
                        line(soilTemperature18, .brown.mix(with: .black, by: 0.4), width: 2.8, label: "18 cm"),
                        line(soilTemperature6, .brown.mix(with: .black, by: 0.25), width: 3.1, label: "6 cm"),
                        line(soilTemperature0, .brown, label: "0 cm")],
                domain: paddedDomain([soilTemperature0, soilTemperature6, soilTemperature18, soilTemperature54]),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
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
                fillsPrimary: false,
                extremes: [],
                extremeFormat: { [moistureUnit = compactMoistureUnit] in
                    "\($0.formatted(.number.precision(.fractionLength(2)))) \(moistureUnit)"
                },
                primaryColor: .blue
            )
        case .evapotranspiration:
            return HourlyLensLayout(
                lines: [line(et0, .hourlyRain)],
                domain: paddedDomain([et0], from: 0, minimumPad: 0.05),
                showsBars: false,
                barsAlpha: 0,
                fillsPrimary: false,
                extremes: extremeMarks(for: et0, highsOnly: true, atLeast: 0.05),
                extremeFormat: { [unit = et0Unit] in
                    "\($0.formatted(.number.precision(.fractionLength(2)))) \(unit)"
                },
                primaryColor: .hourlyRain
            )
        }
    }

    private func line(
        _ values: [Double],
        _ color: Color,
        width: CGFloat = 4,
        dashed: Bool = false,
        opacity: Double = 1,
        label: String? = nil
    ) -> HourlyLensLayout.Line {
        HourlyLensLayout.Line(
            values: values, color: color, width: width, dashed: dashed, opacity: opacity, label: label
        )
    }

    /// Joint min/max over all series, padded so curves don't kiss the edges.
    /// `from` pins the lower bound (wind and ET₀ start at zero).
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
