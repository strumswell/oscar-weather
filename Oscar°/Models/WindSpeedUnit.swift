import Foundation

enum WindSpeedUnit: String {
  case kmh
  case ms
  case mph
  case kn
  case bft

  init(settingValue: String?) {
    self = WindSpeedUnit(rawValue: settingValue ?? "") ?? .kmh
  }

  var apiRawValue: String {
    switch self {
    case .bft:
      return WindSpeedUnit.kmh.rawValue
    default:
      return rawValue
    }
  }

  var displayUnit: String {
    switch self {
    case .kmh:
      return "km/h"
    case .ms:
      return "m/s"
    case .mph:
      return "mph"
    case .kn:
      return "kn"
    case .bft:
      return "Bft"
    }
  }

  var usesBeaufortDisplay: Bool {
    self == .bft
  }
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
    case ..<1:
      return 0
    case ..<6:
      return 1
    case ..<12:
      return 2
    case ..<20:
      return 3
    case ..<29:
      return 4
    case ..<39:
      return 5
    case ..<50:
      return 6
    case ..<62:
      return 7
    case ..<75:
      return 8
    case ..<89:
      return 9
    case ..<103:
      return 10
    case ..<118:
      return 11
    default:
      return 12
    }
  }

  static func value(forKilometersPerHour speed: Double?) -> Double? {
    guard let speed else { return nil }
    return Double(force(forKilometersPerHour: speed))
  }

  static func entry(forKilometersPerHour speed: Double?) -> Entry? {
    guard let speed else { return nil }
    return entry(forForce: force(forKilometersPerHour: speed))
  }

  static func entry(forForce force: Int) -> Entry {
    entries[min(max(force, 0), 12)]
  }

  static func convertedValues(fromKilometersPerHour values: [Double]) -> [Double] {
    values.map { Double(force(forKilometersPerHour: $0)) }
  }

  static func convertedValues(fromKilometersPerHour values: [Double?]) -> [Double?] {
    values.map { value(forKilometersPerHour: $0) }
  }
}

enum WindSpeedFormatter {
  static func string(_ value: Double?, unit: String) -> String {
    guard let value else { return "--" }
    if unit == WindSpeedUnit.bft.displayUnit {
      return "\(Int(value.rounded())) \(unit)"
    }
    return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
  }
}
