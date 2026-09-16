import SwiftUI

/// A user-selectable weather model for the forecast request.
///
/// The raw value is the Open-Meteo `models` identifier and must stay in sync with the
/// `models` enum in `openapi.yml` (which generates `Operations.getForecast.Input.Query.modelsPayload`).
enum ForecastModelPreference: String, CaseIterable, Identifiable {
  case bestMatch = "best_match"

  case ecmwfIFS = "ecmwf_ifs"
  case ecmwfIFS025 = "ecmwf_ifs025"
  case ecmwfAIFS = "ecmwf_aifs025_single"

  case dwdICON = "icon_seamless"
  case noaaGFS = "gfs_seamless"
  case meteoFrance = "meteofrance_seamless"
  case ukmo = "ukmo_seamless"
  case kma = "kma_seamless"
  case jma = "jma_seamless"
  case meteoSwiss = "meteoswiss_icon_seamless"
  case metNorway = "metno_seamless"
  case gem = "gem_seamless"
  case bom = "bom_access_global"
  case cma = "cma_grapes_global"
  case knmi = "knmi_seamless"
  case dmi = "dmi_seamless"
  case italiaMeteo = "italia_meteo_arpae_icon_2i"

  var id: String { rawValue }

  /// The value sent as the Open-Meteo `models` query parameter.
  var apiValue: String { rawValue }

  enum Group: CaseIterable, Identifiable {
    case automatic
    case ecmwf
    case national

    var id: Self { self }

    var models: [ForecastModelPreference] {
      ForecastModelPreference.allCases.filter { $0.group == self }
    }

    var header: LocalizedStringKey? {
      switch self {
      case .automatic: return nil
      case .ecmwf: return "ECMWF"
      case .national: return "Nationale Wetterdienste"
      }
    }
  }

  var group: Group {
    switch self {
    case .bestMatch: return .automatic
    case .ecmwfIFS, .ecmwfIFS025, .ecmwfAIFS: return .ecmwf
    default: return .national
    }
  }

  /// Short, user-facing name. Provider/model names are proper nouns and stay untranslated.
  var name: String {
    switch self {
    case .bestMatch: return String(localized: "Automatisch")
    case .ecmwfIFS: return "ECMWF IFS HRES"
    case .ecmwfIFS025: return "ECMWF IFS 0.25°"
    case .ecmwfAIFS: return "ECMWF AIFS 0.25°"
    case .dwdICON: return "DWD ICON"
    case .noaaGFS: return "NOAA GFS & HRRR"
    case .meteoFrance: return "Météo-France ARPEGE & AROME"
    case .ukmo: return "UK Met Office"
    case .kma: return "KMA"
    case .jma: return "JMA MSM & GSM"
    case .meteoSwiss: return "MeteoSwiss ICON CH"
    case .metNorway: return "MET Norway Nordic"
    case .gem: return "GEM"
    case .bom: return "BOM ACCESS-G"
    case .cma: return "CMA GFS GRAPES"
    case .knmi: return "KNMI HARMONIE"
    case .dmi: return "DMI HARMONIE"
    case .italiaMeteo: return "ItaliaMeteo ARPAE"
    }
  }

  /// Operating agency, shown as a subtitle next to the flag.
  var provider: String? {
    switch self {
    case .bestMatch: return nil
    case .ecmwfIFS, .ecmwfIFS025, .ecmwfAIFS: return "ECMWF"
    case .dwdICON: return "Deutscher Wetterdienst"
    case .noaaGFS: return "NOAA"
    case .meteoFrance: return "Météo-France"
    case .ukmo: return "UK Met Office"
    case .kma: return "Korea Meteorological Administration"
    case .jma: return "Japan Meteorological Agency"
    case .meteoSwiss: return "MeteoSwiss"
    case .metNorway: return "MET Norway"
    case .gem: return "Canadian Weather Service"
    case .bom: return "Bureau of Meteorology"
    case .cma: return "China Meteorological Administration"
    case .knmi: return "KNMI"
    case .dmi: return "DMI"
    case .italiaMeteo: return "ItaliaMeteo"
    }
  }

  /// The individual models combined into this prediction (proper nouns, untranslated).
  var combinedModels: String? {
    switch self {
    case .dwdICON: return "ICON Global · ICON EU · ICON D2"
    case .noaaGFS: return "GFS Global · HRRR"
    case .meteoFrance: return "ARPEGE World/Europe · AROME France"
    case .ukmo: return "Global 10 km · UK 2 km"
    case .kma: return "GDPS · LDPS"
    case .jma: return "GSM · MSM"
    case .meteoSwiss: return "ICON CH1 · ICON CH2"
    case .metNorway: return "MET Nordic · ECMWF IFS"
    case .gem: return "GEM Global · Regional · HRDPS"
    case .knmi: return "HARMONIE AROME · ECMWF IFS"
    case .dmi: return "HARMONIE AROME · ECMWF IFS"
    default: return nil
    }
  }

  /// One-line description for models that don't combine several sub-models.
  var summary: LocalizedStringKey? {
    switch self {
    case .bestMatch:
      return "Wählt für jeden Ort weltweit automatisch das beste Modell und kombiniert mehrere Wetterdienste."
    case .ecmwfIFS:
      return "Native 9-km-Auflösung direkt von ECMWF, stündlich bis +90 Std."
    case .ecmwfIFS025:
      return "Globales 0,25°-Modell (Open-Data, ca. 2 Std. Verzögerung)."
    case .ecmwfAIFS:
      return "KI-basiertes Wettermodell von ECMWF."
    case .metNorway, .knmi, .dmi:
      return "Hochauflösendes Regionalmodell, weltweit durch ECMWF ergänzt."
    case .bom:
      return "Globales Modell des australischen Wetterdienstes."
    case .cma:
      return "Globales Modell des chinesischen Wetterdienstes."
    case .italiaMeteo:
      return "Hochauflösendes Modell für Italien."
    default:
      return nil
    }
  }

  // MARK: - Technical specs (from the provider model overview)

  private var resolutionMinKm: Double? {
    switch self {
    case .bestMatch: return nil
    case .ecmwfIFS: return 9
    case .ecmwfIFS025, .ecmwfAIFS: return 25
    case .dwdICON: return 2
    case .noaaGFS: return 3
    case .meteoFrance: return 1
    case .ukmo: return 2
    case .kma: return 1.5
    case .jma: return 5
    case .meteoSwiss: return 1
    case .metNorway: return 1
    case .gem: return 2.5
    case .bom: return 15
    case .cma: return 15
    case .knmi: return 2
    case .dmi: return 2
    case .italiaMeteo: return 2
    }
  }

  private var resolutionMaxKm: Double? {
    switch self {
    case .dwdICON: return 11
    case .noaaGFS: return 25
    case .meteoFrance: return 25
    case .ukmo: return 10
    case .kma: return 13
    case .jma: return 55
    case .meteoSwiss: return 2
    default: return nil
    }
  }

  /// Maximum forecast horizon in days.
  private var forecastDays: Double? {
    switch self {
    case .bestMatch: return nil
    case .ecmwfIFS, .ecmwfIFS025, .ecmwfAIFS: return 15
    case .dwdICON: return 7.5
    case .noaaGFS: return 16
    case .meteoFrance: return 4
    case .ukmo: return 7
    case .kma: return 12
    case .jma: return 11
    case .meteoSwiss: return 5
    case .metNorway: return 2.5
    case .gem: return 10
    case .bom: return 10
    case .cma: return 10
    case .knmi: return 2.5
    case .dmi: return 2.5
    case .italiaMeteo: return 3
    }
  }

  /// Update cadence in hours.
  private var updateHours: Int? {
    switch self {
    case .bestMatch: return nil
    case .ecmwfIFS, .ecmwfIFS025, .ecmwfAIFS: return 6
    case .dwdICON: return 3
    case .noaaGFS: return 1
    case .meteoFrance: return 1
    case .ukmo: return 1
    case .kma: return 6
    case .jma: return 3
    case .meteoSwiss: return 3
    case .metNorway: return 1
    case .gem: return 6
    case .bom: return 6
    case .cma: return 6
    case .knmi: return 1
    case .dmi: return 3
    case .italiaMeteo: return 12
    }
  }

  var resolutionText: String? {
    guard let min = resolutionMinKm else { return nil }
    if let max = resolutionMaxKm, max != min {
      return "\(min.formatted())–\(max.formatted()) km"
    }
    return "\(min.formatted()) km"
  }

  var forecastLengthText: String? {
    guard let days = forecastDays else { return nil }
    return String(localized: "\(days.formatted()) Tage")
  }

  var updateFrequencyText: String? {
    guard let hours = updateHours else { return nil }
    if hours <= 1 { return String(localized: "stündlich") }
    return String(localized: "alle \(hours) Std.")
  }

  /// The home region a model is optimized for. Most models still deliver worldwide data;
  /// see `regionalOnly` for the few that don't.
  var optimizedRegion: String? {
    switch self {
    case .dwdICON: return String(localized: "Europa")
    case .noaaGFS: return String(localized: "USA")
    case .meteoFrance: return String(localized: "Frankreich & Europa")
    case .ukmo: return String(localized: "Großbritannien")
    case .kma: return String(localized: "Korea")
    case .jma: return String(localized: "Japan")
    case .meteoSwiss: return String(localized: "Mitteleuropa & Alpen")
    case .metNorway: return String(localized: "Nordeuropa")
    case .gem: return String(localized: "Nordamerika")
    case .bom: return String(localized: "Australien")
    case .cma: return String(localized: "China")
    case .knmi: return String(localized: "Niederlande & Westeuropa")
    case .dmi: return String(localized: "Nordeuropa")
    case .italiaMeteo: return String(localized: "Italien")
    default: return nil
    }
  }

  /// `true` when the model only covers its home region and returns no data elsewhere
  /// (no global model and no ECMWF fallback).
  var regionalOnly: Bool {
    switch self {
    case .meteoSwiss, .italiaMeteo: return true
    default: return false
    }
  }
}
