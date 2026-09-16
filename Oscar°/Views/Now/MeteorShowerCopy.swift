import Foundation

enum MeteorShowerForecast {
  /// The hourly notice for the server's best shower tonight, placed at the
  /// start of its observing window, or now while the window is under way.
  /// Nights the server rates as unobservable or of low meteor activity (a
  /// stream far from its peak) get no notice.
  static func notice(
    in response: MeteorShowerResponse,
    now: Date = .now
  ) -> (event: MeteorShowerEvent, date: Date)? {
    guard let event = response.primaryShower,
      event.condition.lowercased() != "unobservable",
      !(response.reasons ?? []).contains("low_activity"),
      let window = event.bestWindow,
      window.start < window.end,
      window.end > now
    else { return nil }
    return (event, max(window.start, now))
  }
}

/// How close tonight is to a shower's peak. Measured from the middle of the
/// night's darkness so a peak shortly after midnight still counts as tonight.
enum MeteorShowerPhase: Equatable, Sendable {
  case peakTonight
  case nearPeak
  case active

  static func of(
    _ event: MeteorShowerEvent,
    night: MeteorShowerNight?,
    now: Date = .now
  ) -> MeteorShowerPhase {
    var reference = now
    if let start = night?.darknessStart, let end = night?.darknessEnd, end > start {
      reference = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    }
    let hours = abs(event.peak.timeIntervalSince(reference)) / 3600
    if hours <= 12 { return .peakTonight }
    if hours <= 36 { return .nearPeak }
    return .active
  }
}

/// App-localized display copy for semantic API values. Unknown values fall
/// back to neutral copy rather than exposing backend enum strings.
enum MeteorShowerCopy {
  static func observingConditionText(
    for condition: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch condition?.lowercased() {
    case "good":
      localized("meteor.observing.good", defaultValue: "Gute Bedingungen", locale: locale)
    case "fair":
      localized("meteor.observing.fair", defaultValue: "Mäßige Bedingungen", locale: locale)
    case "poor":
      localized("meteor.observing.poor", defaultValue: "Ungünstige Bedingungen", locale: locale)
    case "unobservable":
      localized("meteor.observing.unobservable", defaultValue: "Kein Beobachtungsfenster", locale: locale)
    case "unavailable":
      localized("meteor.observing.unavailable", defaultValue: "Einschätzung nicht verfügbar", locale: locale)
    default:
      localized("meteor.observing.unknown", defaultValue: "Wetterbedingungen unklar", locale: locale)
    }
  }

  static func observingExplanation(
    for condition: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch condition?.lowercased() {
    case "good":
      localized(
        "meteor.observing.explanation.good",
        defaultValue: "Wetter und Mondlicht sprechen für eine gute Sicht im angegebenen Zeitfenster.",
        locale: locale
      )
    case "fair":
      localized(
        "meteor.observing.explanation.fair",
        defaultValue: "Sternschnuppen sind möglich. Wetter, Mondlicht oder die Position am Himmel können die Sicht einschränken.",
        locale: locale
      )
    case "poor":
      localized(
        "meteor.observing.explanation.poor",
        defaultValue: "Wetter, Mondlicht oder die Position am Himmel erschweren die Beobachtung im angegebenen Zeitfenster.",
        locale: locale
      )
    case "unobservable":
      localized(
        "meteor.observing.explanation.unobservable",
        defaultValue: "Für diese Nacht ist kein geeignetes Beobachtungsfenster mehr verfügbar.",
        locale: locale
      )
    case "unavailable":
      localized(
        "meteor.observing.explanation.unavailable",
        defaultValue: "Die Daten reichen derzeit nicht für eine aktuelle Beobachtungsempfehlung aus.",
        locale: locale
      )
    default:
      localized(
        "meteor.observing.explanation.unknown",
        defaultValue: "Für die Beobachtungszeit liegen keine verlässlichen Wetterdaten vor. Die astronomische Sichtbarkeit allein sagt nichts über die Bewölkung aus.",
        locale: locale
      )
    }
  }

  static func bannerText(
    for phase: MeteorShowerPhase,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch phase {
    case .peakTonight:
      localized("meteor.banner.peakTonight", defaultValue: "Sternschnuppen heute Nacht", locale: locale)
    case .nearPeak:
      localized("meteor.banner.nearPeak", defaultValue: "Sternschnuppen möglich", locale: locale)
    case .active:
      localized("meteor.banner.active", defaultValue: "Sternschnuppen aktiv", locale: locale)
    }
  }

  static func detailPeakText(
    for phase: MeteorShowerPhase,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch phase {
    case .peakTonight:
      localized("meteor.status.tonight", defaultValue: "Heute Nacht", locale: locale)
    case .nearPeak:
      localized("meteor.status.nearPeak", defaultValue: "Nahe am Höhepunkt", locale: locale)
    case .active:
      localized("meteor.status.active", defaultValue: "Aktiv", locale: locale)
    }
  }

  static func showerName(
    for id: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch id.uppercased() {
    case "QUA":
      localized("meteor.shower.quadrantids", defaultValue: "Quadrantiden", locale: locale)
    case "LYR":
      localized("meteor.shower.lyrids", defaultValue: "Lyriden", locale: locale)
    case "ETA":
      localized("meteor.shower.etaAquariids", defaultValue: "Eta-Aquariiden", locale: locale)
    case "SDA":
      localized(
        "meteor.shower.southernDeltaAquariids",
        defaultValue: "Südliche Delta-Aquariiden",
        locale: locale
      )
    case "PER":
      localized("meteor.shower.perseids", defaultValue: "Perseiden", locale: locale)
    case "ORI":
      localized("meteor.shower.orionids", defaultValue: "Orioniden", locale: locale)
    case "LEO":
      localized("meteor.shower.leonids", defaultValue: "Leoniden", locale: locale)
    case "GEM":
      localized("meteor.shower.geminids", defaultValue: "Geminiden", locale: locale)
    case "URS":
      localized("meteor.shower.ursids", defaultValue: "Ursiden", locale: locale)
    default:
      id
    }
  }

  /// Provider names behind the server's weather rating, cloud model first.
  /// Proper names are not localized; unknown sources are omitted.
  static func weatherSourceNames(for weather: MeteorShowerWeatherSource) -> [String] {
    var names: [String] = []
    switch weather.source.lowercased() {
    case "ecmwf":
      names.append("ECMWF")
    case "meteosat-nowcast":
      // The satellite nowcast only ever raises the ECMWF cloud value.
      names += ["ECMWF", "EUMETSAT"]
    default:
      break
    }
    let radar: String? = switch weather.precipitationSource?.lowercased() {
    case "dwd-nowcast": "DWD"
    case "opera-nowcast": "EUMETNET OPERA"
    case "mrms-nowcast": "NOAA MRMS"
    case "cwa-nowcast": "CWA"
    case "redemet-nowcast": "REDEMET"
    case "aemet-nowcast": "AEMET"
    default: nil
    }
    if let radar { names.append(radar) }
    return names
  }

  /// `String(localized:locale:)` uses `locale` for formatting but the process
  /// language for resource selection. An explicit lproj keeps locale-driven
  /// previews and tests deterministic.
  private static func localized(
    _ key: StaticString,
    defaultValue: String.LocalizationValue,
    locale: Locale
  ) -> String {
    let languageCode = locale.language.languageCode?.identifier
    let bundle = languageCode
      .flatMap { Bundle.main.url(forResource: $0, withExtension: "lproj") }
      .flatMap(Bundle.init(url:)) ?? .main
    return String(
      localized: key,
      defaultValue: defaultValue,
      bundle: bundle,
      locale: locale
    )
  }
}
