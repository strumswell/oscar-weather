import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    func rounded(_ celsius: Double) -> Int {
        Int(value(fromCelsius: celsius).rounded())
    }

    func string(_ celsius: Double) -> String {
        "\(rounded(celsius))°"
    }

    func delta(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5
        }
    }

    func celsius(fromValue value: Double) -> Double {
        switch self {
        case .celsius: value
        case .fahrenheit: (value - 32) * 5 / 9
        }
    }

    static var localeDefault: TemperatureUnit {
        UnitTemperature(forLocale: .current) == .fahrenheit ? .fahrenheit : .celsius
    }
}

enum WindSpeedUnit: String, CaseIterable, Identifiable {
    case kmh
    case ms
    case mph
    case kn
    case bft

    var id: String { rawValue }

    var symbol: String { Self.symbols[self] ?? rawValue }

    private static let symbols: [WindSpeedUnit: String] = [
        .kmh: localizedSymbol(UnitSpeed.kilometersPerHour),
        .ms: localizedSymbol(UnitSpeed.metersPerSecond),
        .mph: "mph",
        .kn: localizedSymbol(UnitSpeed.knots),
        .bft: "Bft",
    ]

    func value(fromKilometersPerHour speed: Double) -> Double {
        switch self {
        case .kmh: speed
        case .ms: speed / 3.6
        case .mph: speed / 1.609344
        case .kn: speed / 1.852
        case .bft: Double(BeaufortScale.force(forKilometersPerHour: speed))
        }
    }

    static var localeDefault: WindSpeedUnit {
        switch UnitSpeed(forLocale: .current, usage: .wind) {
        case .milesPerHour: .mph
        case .metersPerSecond: .ms
        case .knots: .kn
        default: .kmh
        }
    }
}

enum PrecipitationUnit: String, CaseIterable, Identifiable {
    case mm
    case inch

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .mm: Self.millimeters
        case .inch: Self.inches
        }
    }

    var rateSymbol: String { "\(symbol)/h" }

    var snowSymbol: String {
        switch self {
        case .mm: Self.centimeters
        case .inch: Self.inches
        }
    }

    var fractionDigits: Int {
        switch self {
        case .mm: 1
        case .inch: 2
        }
    }

    func value(fromMillimeters millimeters: Double) -> Double {
        switch self {
        case .mm: millimeters
        case .inch: millimeters / 25.4
        }
    }

    func snow(fromCentimeters centimeters: Double) -> Double {
        switch self {
        case .mm: centimeters
        case .inch: centimeters / 2.54
        }
    }

    static var localeDefault: PrecipitationUnit {
        UnitLength(forLocale: .current, usage: .rainfall) == .inches ? .inch : .mm
    }

    private static let millimeters = localizedSymbol(UnitLength.millimeters)
    private static let centimeters = localizedSymbol(UnitLength.centimeters)
    private static let inches = "in"
}

enum PressureUnit: String, CaseIterable, Identifiable {
    case hpa
    case inhg
    case mmhg

    var id: String { rawValue }

    var symbol: String { Self.symbols[self] ?? rawValue }

    private static let symbols: [PressureUnit: String] = [
        .hpa: localizedSymbol(UnitPressure.hectopascals),
        .inhg: localizedSymbol(UnitPressure.inchesOfMercury),
        .mmhg: localizedSymbol(UnitPressure.millimetersOfMercury),
    ]

    var fractionDigits: Int {
        switch self {
        case .hpa, .mmhg: 0
        case .inhg: 2
        }
    }

    func value(fromHectopascals hectopascals: Double) -> Double {
        switch self {
        case .hpa: hectopascals
        case .inhg: hectopascals / 33.8639
        case .mmhg: hectopascals / 1.333224
        }
    }

    static var localeDefault: PressureUnit {
        switch UnitPressure(forLocale: .current, usage: .barometric) {
        case .inchesOfMercury: .inhg
        case .millimetersOfMercury: .mmhg
        default: .hpa
        }
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case km
    case mi

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .km: Self.kilometers
        case .mi: Self.miles
        }
    }

    var areaSymbol: String {
        switch self {
        case .km: Self.squareKilometers
        case .mi: Self.squareMiles
        }
    }

    func value(fromKilometers kilometers: Double) -> Double {
        switch self {
        case .km: kilometers
        case .mi: kilometers / 1.609344
        }
    }

    func area(fromSquareKilometers squareKilometers: Double) -> Double {
        switch self {
        case .km: squareKilometers
        case .mi: squareKilometers / 2.589988
        }
    }

    static var localeDefault: DistanceUnit {
        UnitLength(forLocale: .current, usage: .road) == .miles ? .mi : .km
    }

    private static let kilometers = localizedSymbol(UnitLength.kilometers)
    private static let miles = localizedSymbol(UnitLength.miles)
    private static let squareKilometers = localizedSymbol(UnitArea.squareKilometers)
    private static let squareMiles = localizedSymbol(UnitArea.squareMiles)
}

struct Units: Equatable {
    var temperature: TemperatureUnit
    var wind: WindSpeedUnit
    var precipitation: PrecipitationUnit
    var pressure: PressureUnit
    var distance: DistanceUnit

    static let metric = Units(temperature: .celsius, wind: .kmh, precipitation: .mm, pressure: .hpa, distance: .km)

    func temperatureString(_ celsius: Double?, placeholder: String = "") -> String {
        celsius.map(temperature.string) ?? placeholder
    }

    func preciseTemperatureString(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return "\(number(temperature.value(fromCelsius: celsius), digits: 1))°"
    }

    func windValue(_ kilometersPerHour: Double) -> Double {
        wind.value(fromKilometersPerHour: kilometersPerHour)
    }

    func windNumber(_ kilometersPerHour: Double) -> String {
        number(windValue(kilometersPerHour), digits: wind == .ms ? 1 : 0)
    }

    func windString(_ kilometersPerHour: Double?) -> String {
        guard let kilometersPerHour else { return "–" }
        return "\(windNumber(kilometersPerHour)) \(wind.symbol)"
    }

    func precipitationNumber(_ millimeters: Double) -> String {
        let value = precipitation.value(fromMillimeters: millimeters)
        let smallest = pow(10, -Double(precipitation.fractionDigits))
        guard value <= 0 || value >= smallest / 2 else {
            return "<\(number(smallest, digits: precipitation.fractionDigits))"
        }
        return number(value, digits: precipitation.fractionDigits)
    }

    func precipitationString(_ millimeters: Double?) -> String {
        guard let millimeters else { return "–" }
        return "\(precipitationNumber(millimeters)) \(precipitation.symbol)"
    }

    func rateString(_ millimetersPerHour: Double?) -> String {
        guard let millimetersPerHour else { return "–" }
        return "\(precipitationNumber(millimetersPerHour)) \(precipitation.rateSymbol)"
    }

    func snowString(_ centimeters: Double?) -> String {
        guard let centimeters else { return "–" }
        return "\(number(precipitation.snow(fromCentimeters: centimeters), digits: precipitation.fractionDigits)) \(precipitation.snowSymbol)"
    }

    func pressureNumber(_ hectopascals: Double) -> String {
        number(pressure.value(fromHectopascals: hectopascals), digits: pressure.fractionDigits)
    }

    func pressureString(_ hectopascals: Double?) -> String {
        guard let hectopascals else { return "–" }
        return "\(pressureNumber(hectopascals)) \(pressure.symbol)"
    }

    func distanceString(_ kilometers: Double?) -> String {
        guard let kilometers else { return "–" }
        return "\(number(distance.value(fromKilometers: kilometers), digits: 1)) \(distance.symbol)"
    }

    func areaString(_ squareKilometers: Double?) -> String {
        guard let squareKilometers else { return "–" }
        return "\(number(distance.area(fromSquareKilometers: squareKilometers), digits: 0)) \(distance.areaSymbol)"
    }

    private func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(digits)))
    }
}

private let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

private func localizedSymbol<UnitType: Dimension>(_ unit: UnitType) -> String {
    let text = Measurement(value: 1, unit: unit)
        .formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(appLocale).attributed)
    let symbol = text.runs
        .filter { $0.measurement == .unit }
        .map { String(text[$0.range].characters) }
        .joined()
    return symbol.isEmpty ? unit.symbol : symbol
}

enum BeaufortScale {
    struct Entry: Identifiable {
        let force: Int
        let name: String
        let range: String
        let landMeaning: String
        let colorHex: Int

        var id: Int { force }
        var title: String { "\(force) Bft · \(name)" }
    }

    static let entries: [Entry] = [
        Entry(force: 0, name: String(localized: "Windstille"), range: "< 1 km/h", landMeaning: String(localized: "Rauch steigt fast senkrecht auf."), colorHex: 0xFFFFFF),
        Entry(force: 1, name: String(localized: "Leiser Zug"), range: "1-5 km/h", landMeaning: String(localized: "Rauch driftet leicht, Windfahnen bleiben ruhig."), colorHex: 0xAEF1F9),
        Entry(force: 2, name: String(localized: "Leichte Brise"), range: "6-11 km/h", landMeaning: String(localized: "Blätter rascheln, Wind ist im Gesicht spürbar."), colorHex: 0x96F7DC),
        Entry(force: 3, name: String(localized: "Schwache Brise"), range: "12-19 km/h", landMeaning: String(localized: "Dünne Zweige bewegen sich, Wimpel strecken sich."), colorHex: 0x96F7B4),
        Entry(force: 4, name: String(localized: "Mäßige Brise"), range: "20-28 km/h", landMeaning: String(localized: "Zweige bewegen sich, loses Papier hebt ab."), colorHex: 0x6FF46F),
        Entry(force: 5, name: String(localized: "Frische Brise"), range: "29-38 km/h", landMeaning: String(localized: "Größere Zweige und kleine Bäume bewegen sich."), colorHex: 0x73ED12),
        Entry(force: 6, name: String(localized: "Starker Wind"), range: "39-49 km/h", landMeaning: String(localized: "Dicke Äste bewegen sich, Drähte können pfeifen."), colorHex: 0xA4ED12),
        Entry(force: 7, name: String(localized: "Steifer Wind"), range: "50-61 km/h", landMeaning: String(localized: "Bäume schwanken, Gehen gegen den Wind wird mühsam."), colorHex: 0xDAED12),
        Entry(force: 8, name: String(localized: "Stürmischer Wind"), range: "62-74 km/h", landMeaning: String(localized: "Große Bäume bewegen sich, Zweige können brechen."), colorHex: 0xEDC212),
        Entry(force: 9, name: String(localized: "Sturm"), range: "75-88 km/h", landMeaning: String(localized: "Äste brechen, kleinere Schäden sind möglich."), colorHex: 0xED8F12),
        Entry(force: 10, name: String(localized: "Schwerer Sturm"), range: "89-102 km/h", landMeaning: String(localized: "Bäume können entwurzeln, Gebäude können Schaden nehmen."), colorHex: 0xED6312),
        Entry(force: 11, name: String(localized: "Orkanartiger Sturm"), range: "103-117 km/h", landMeaning: String(localized: "Schwere Sturmschäden, im Binnenland selten."), colorHex: 0xED2912),
        Entry(force: 12, name: String(localized: "Orkan"), range: ">= 118 km/h", landMeaning: String(localized: "Schwere Verwüstungen, sehr selten im Landesinneren."), colorHex: 0xD5102D),
    ]

    static func force(forKilometersPerHour speed: Double) -> Int {
        switch max(0, speed) {
        case ..<1: 0
        case ..<6: 1
        case ..<12: 2
        case ..<20: 3
        case ..<29: 4
        case ..<39: 5
        case ..<50: 6
        case ..<62: 7
        case ..<75: 8
        case ..<89: 9
        case ..<103: 10
        case ..<118: 11
        default: 12
        }
    }

    static func entry(forKilometersPerHour speed: Double?) -> Entry? {
        guard let speed else { return nil }
        return entry(forForce: force(forKilometersPerHour: speed))
    }

    static func entry(forForce force: Int) -> Entry {
        entries[min(max(force, 0), 12)]
    }
}
