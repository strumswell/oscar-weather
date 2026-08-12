import Foundation

enum DailyEnsembleModel: String, CaseIterable, Identifiable {
  case ecmwfAIFS025Ensemble = "ecmwf_aifs025_ensemble"
  case ecmwfIFS025Ensemble = "ecmwf_ifs025_ensemble"
  case googleWeatherNext2Ensemble = "google_weathernext2_ensemble"
  case ncepAIGFS025 = "ncep_aigefs025"
  case ncepGEFS05 = "ncep_gefs05"
  case iconGlobalEPS = "icon_global_eps"
  case iconEUEPS = "icon_eu_eps"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .ecmwfAIFS025Ensemble:
      return "AIFS"
    case .ecmwfIFS025Ensemble:
      return "IFS ENS"
    case .googleWeatherNext2Ensemble:
      return "WeatherNext2"
    case .ncepAIGFS025:
      return "AI GEFS"
    case .ncepGEFS05:
      return "GEFS"
    case .iconGlobalEPS:
      return "ICON Global"
    case .iconEUEPS:
      return "ICON EU"
    }
  }

  var region: String {
    switch self {
    case .iconEUEPS:
      return "Europa"
    default:
      return "Global"
    }
  }

  var members: Int {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble:
      return 51
    case .googleWeatherNext2Ensemble:
      return 35
    case .ncepAIGFS025, .ncepGEFS05:
      return 31
    case .iconGlobalEPS, .iconEUEPS:
      return 40
    }
  }

  var menuSubtitle: String {
    switch self {
    case .ecmwfAIFS025Ensemble: return "25 km · 15 Tage"
    case .ecmwfIFS025Ensemble: return "25 km · 15 Tage"
    case .googleWeatherNext2Ensemble: return "25 km · 15 Tage"
    case .ncepAIGFS025: return "25 km · 16 Tage"
    case .ncepGEFS05: return "50 km · 35 Tage"
    case .iconGlobalEPS: return "26 km · 7,5 Tage"
    case .iconEUEPS: return "13 km · 5 Tage"
    }
  }

  enum Provider: String, CaseIterable {
    case ecmwf = "ECMWF"
    case google = "Google"
    case noaa = "NOAA"
    case dwd = "DWD"
  }

  var provider: Provider {
    switch self {
    case .ecmwfAIFS025Ensemble, .ecmwfIFS025Ensemble: return .ecmwf
    case .googleWeatherNext2Ensemble: return .google
    case .ncepAIGFS025, .ncepGEFS05: return .noaa
    case .iconGlobalEPS, .iconEUEPS: return .dwd
    }
  }

  static var modelsByProvider: [(provider: Provider, models: [DailyEnsembleModel])] {
    Provider.allCases.map { provider in
      (provider, DailyEnsembleModel.allCases.filter { $0.provider == provider })
    }
  }
}
