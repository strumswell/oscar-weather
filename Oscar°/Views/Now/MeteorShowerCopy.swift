import Foundation

enum MeteorShowerForecast {
  static func cloudCover(
    nearestTo date: Date,
    timestamps: [Double],
    values: [Double]
  ) -> Double? {
    let count = min(timestamps.count, values.count)
    guard count > 0 else { return nil }
    let target = date.timeIntervalSince1970
    let index = (0..<count).min {
      abs(timestamps[$0] - target) < abs(timestamps[$1] - target)
    }
    return index.map { values[$0] }
  }
}

/// App-localized display copy for semantic API values. Unknown status and
/// visibility values are omitted rather than exposing backend enum strings.
enum MeteorShowerCopy {
  static func bannerText(
    for presentation: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch presentation?.lowercased() {
    case "many_tonight":
      localized(
        "meteor.banner.manyTonight",
        defaultValue: "Heute Nacht viele Sternschnuppen möglich",
        locale: locale
      )
    case "peak_tonight":
      localized(
        "meteor.banner.peakTonight",
        defaultValue: "Sternschnuppen heute Nacht",
        locale: locale
      )
    case "active":
      localized(
        "meteor.banner.active",
        defaultValue: "Sternschnuppen aktiv",
        locale: locale
      )
    case "near_peak", .none, .some:
      localized(
        "meteor.banner.nearPeak",
        defaultValue: "Sternschnuppen möglich",
        locale: locale
      )
    }
  }

  static func visibilityText(
    for classification: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String? {
    switch classification?.lowercased() {
    case "not_visible":
      localized(
        "meteor.visibility.notVisible",
        defaultValue: "Nicht sichtbar",
        locale: locale
      )
    case "poor":
      localized("meteor.visibility.poor", defaultValue: "Schlecht", locale: locale)
    case "fair":
      localized("meteor.visibility.fair", defaultValue: "Mäßig", locale: locale)
    case "good":
      localized("meteor.visibility.good", defaultValue: "Gut", locale: locale)
    case "excellent":
      localized(
        "meteor.visibility.excellent",
        defaultValue: "Ausgezeichnet",
        locale: locale
      )
    default: nil
    }
  }

  /// A plain-language observing hint derived from forecast cloud cover at the
  /// event's best observing time. The astronomical classification above is a
  /// separate signal: even an ideally placed radiant can be hidden by clouds.
  static func cloudVisibilitySentence(
    for cloudCover: Double?,
    locale: Locale = .autoupdatingCurrent
  ) -> String? {
    guard let cloudCover, cloudCover.isFinite else { return nil }
    return switch cloudCover {
    case ...30:
      localized(
        "meteor.visibility.cloud.goodSentence",
        defaultValue: "Wenig Wolken – gute Sicht auf Sternschnuppen.",
        locale: locale
      )
    case ...70:
      localized(
        "meteor.visibility.cloud.mixedSentence",
        defaultValue: "Einige Wolken können die Sicht zeitweise einschränken.",
        locale: locale
      )
    default:
      localized(
        "meteor.visibility.cloud.poorSentence",
        defaultValue: "Viele Wolken – schlechte Sicht auf Sternschnuppen.",
        locale: locale
      )
    }
  }

  static func statusText(
    for status: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String? {
    switch status?.lowercased() {
    case "peak":
      localized("meteor.status.peak", defaultValue: "Höhepunkt", locale: locale)
    case "near_peak":
      localized(
        "meteor.status.nearPeak",
        defaultValue: "Nahe am Höhepunkt",
        locale: locale
      )
    case "active":
      localized("meteor.status.active", defaultValue: "Aktiv", locale: locale)
    default: nil
    }
  }

  static func detailPeakText(
    status: String?,
    presentation: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String? {
    switch presentation?.lowercased() {
    case "many_tonight", "peak_tonight":
      localized("meteor.status.tonight", defaultValue: "Heute Nacht", locale: locale)
    case "near_peak":
      statusText(for: "near_peak", locale: locale)
    case "active":
      statusText(for: "active", locale: locale)
    default:
      statusText(for: status, locale: locale)
    }
  }

  static func showerName(
    for event: MeteorShowerEvent,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch event.id.uppercased() {
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
      event.name
    }
  }

  static func detailExplanation(
    for presentation: String?,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch presentation?.lowercased() {
    case "many_tonight":
      localized(
        "meteor.detail.explanation.manyTonight",
        defaultValue: "Heute Nacht sind besonders viele Sternschnuppen möglich.",
        locale: locale
      )
    case "peak_tonight":
      localized(
        "meteor.detail.explanation.peakTonight",
        defaultValue: "Der Höhepunkt dieses Sternschnuppenschauers ist heute Nacht.",
        locale: locale
      )
    case "active", "near_peak", .none, .some:
      localized(
        "meteor.detail.explanation.active",
        defaultValue: "Heute Nacht sind Sternschnuppen möglich.",
        locale: locale
      )
    }
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
