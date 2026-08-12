import SwiftUI

extension HourlyDetailView {
    func currentValue(from values: [Double]) -> Double? {
        guard let currentIndex, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    func currentValue(from values: [Double?]) -> Double? {
        guard let currentIndex, currentIndex < values.count else { return nil }
        return values[currentIndex]
    }

    func formatted(_ value: Double?, decimals: Int, unit: String) -> String {
        guard let value else { return "--" }
        return "\(value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)"
    }

    func formatted(_ value: Double, decimals: Int, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)"
    }

    func displayedWindSpeeds(_ values: [Double]) -> [Double] {
        guard windSpeedUnit.usesBeaufortDisplay else { return values }
        return BeaufortScale.convertedValues(fromKilometersPerHour: values)
    }

    func displayedWindSpeeds(_ values: [Double?]) -> [Double?] {
        guard windSpeedUnit.usesBeaufortDisplay else { return values }
        return values.map { $0.flatMap(BeaufortScale.value(forKilometersPerHour:)) }
    }

    func apparentTemperatureBadge(for apparentTemperature: Double?, unit: String) -> LocalizedStringKey {
        guard let apparentTemperature else { return "Keine Daten" }
        let value = formatted(apparentTemperature, decimals: 1, unit: unit)
        return "Gefühlt \(value)"
    }

    func precipitationBadge(precipitation: Double?, snowfall: Double?) -> LocalizedStringKey {
        guard let precipitation else { return "Keine Daten" }
        if let snowfall, snowfall > 0 {
            return "Schnee"
        }
        return precipitation > 0 ? "Regen" : "Trocken"
    }

    func humidityBadge(for humidity: Double?) -> LocalizedStringKey {
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

    func humidityColor(for humidity: Double?) -> Color {
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

    func pressureBadge(for pressure: [Double]) -> LocalizedStringKey {
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

    func evapotranspirationExplanation(for et0: [Double], unit: String) -> LocalizedStringKey {
        let total = evapotranspirationTotalForReferenceDay(from: et0)
        let formattedTotal = formatted(total, decimals: 1, unit: unit)
        let liters = total.formatted(.number.precision(.fractionLength(1)))

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

    func windDirectionName(for degrees: Double) -> String {
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
}
