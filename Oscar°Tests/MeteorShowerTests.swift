import Foundation
import CoreLocation
import Testing
@testable import Oscar_

struct MeteorShowerDecodingTests {
  @Test
  func decodesRatedNightAndIgnoresUnknownFields() throws {
    let response = try MeteorShowerResponse.decode(from: Data(Self.ratedNight.utf8))

    #expect(response.condition == "good")
    #expect(response.validUntil == Self.date("2026-08-13T01:00:00Z"))
    #expect(response.reasons == nil)
    #expect(response.night.type == "astronomical")
    #expect(response.night.darknessStart == Self.date("2026-08-12T20:58:00Z"))
    #expect(response.weather.source == "meteosat-nowcast")
    #expect(response.weather.issuedAt == Self.date("2026-08-12T12:00:00Z"))
    #expect(response.weather.precipitationSource == "dwd-nowcast")

    let window = try #require(response.bestWindow)
    #expect(window.shower == "PER")
    #expect(window.start == Self.date("2026-08-13T00:30:00Z"))
    #expect(window.end == Self.date("2026-08-13T01:00:00Z"))
    #expect(window.radiantAltitude == 55.6)
    #expect(window.moonIllumination == 0.0012)
    #expect(window.cloudCover == 15)
    #expect(window.precipitationMmH == 0)

    #expect(response.showers.map(\.id) == ["SDA", "PER"])
    let perseids = try #require(response.primaryShower)
    #expect(perseids.id == "PER")
    #expect(perseids.peak == Self.date("2026-08-13T02:00:00Z"))
    #expect(perseids.uncertaintyHours == 3)
    #expect(!perseids.isPeakEstimated)
    #expect(perseids.bestWindow == window)
    #expect(response.showers[0].isPeakEstimated)
    #expect(response.showers[0].bestWindow == nil)
  }

  /// Verbatim `/astro/meteors` answer for a night without an active stream.
  @Test
  func decodesNightWithoutActiveShower() throws {
    let response = try MeteorShowerResponse.decode(from: Data(#"""
    {"showers":[],"condition":"unobservable","weather":{"source":"none"},"valid_until":"2026-09-17T02:44:40Z","night":{"darkness_end":"2026-09-17T02:44:40Z","type":"astronomical","darkness_start":"2026-09-16T19:18:12Z"},"reasons":["no_active_shower"]}
    """#.utf8))

    #expect(response.condition == "unobservable")
    #expect(response.showers.isEmpty)
    #expect(response.bestWindow == nil)
    #expect(response.primaryShower == nil)
    #expect(response.weather.source == "none")
    #expect(response.weather.issuedAt == nil)
    #expect(response.reasons == ["no_active_shower"])
  }

  @Test
  func decodesPolarNightWithoutDarknessBounds() throws {
    let response = try MeteorShowerResponse.decode(from: Data(#"""
    {"condition":"unobservable","night":{"type":"none"},"showers":[{"id":"PER","peak":"2026-08-13T02:00:00Z","uncertainty_hours":3,"condition":"unobservable"}],"weather":{"source":"none"},"valid_until":"2026-08-13T12:00:00Z","reasons":["no_darkness"]}
    """#.utf8))

    #expect(response.night.darknessStart == nil)
    #expect(response.night.darknessEnd == nil)
    #expect(response.showers.first?.bestWindow == nil)
    #expect(response.primaryShower == nil)
  }

  @Test
  func rejectsMissingRequiredFieldsAndInvalidDates() {
    for broken in [
      Self.ratedNight.replacingOccurrences(of: #""condition": "good","#, with: ""),
      Self.ratedNight.replacingOccurrences(of: #""valid_until": "2026-08-13T01:00:00Z","#, with: ""),
      Self.ratedNight.replacingOccurrences(of: "2026-08-13T02:00:00Z", with: "2026-08-13"),
    ] {
      #expect(throws: DecodingError.self) {
        try MeteorShowerResponse.decode(from: Data(broken.utf8))
      }
    }
  }

  static func date(_ value: String) -> Date {
    try! Date(value, strategy: .iso8601)
  }

  private static let ratedNight = #"""
  {
    "condition": "good",
    "best_window": {
      "start": "2026-08-13T00:30:00Z", "end": "2026-08-13T01:00:00Z", "shower": "PER",
      "radiant_altitude": 55.6, "moon_illumination": 0.0012, "cloud_cover": 15,
      "precipitation_mm_h": 0
    },
    "night": {
      "darkness_start": "2026-08-12T20:58:00Z", "darkness_end": "2026-08-13T01:48:00Z",
      "type": "astronomical"
    },
    "showers": [
      { "id": "SDA", "peak": "2026-07-31T12:00:00Z", "uncertainty_hours": 24, "condition": "unobservable" },
      {
        "id": "PER", "peak": "2026-08-13T02:00:00Z", "uncertainty_hours": 3, "condition": "good",
        "best_window": {
          "start": "2026-08-13T00:30:00Z", "end": "2026-08-13T01:00:00Z", "shower": "PER",
          "radiant_altitude": 55.6, "moon_illumination": 0.0012, "cloud_cover": 15,
          "precipitation_mm_h": 0
        },
        "future_shower_field": true
      }
    ],
    "weather": {
      "source": "meteosat-nowcast", "issued_at": "2026-08-12T12:00:00Z",
      "precipitation_source": "dwd-nowcast"
    },
    "valid_until": "2026-08-13T01:00:00Z",
    "future_root_field": [1, 2, 3]
  }
  """#
}

struct MeteorShowerRequestTests {
  @Test
  func requestTargetsOscarServerWithRoundedCoordinatesOnly() throws {
    let request = try APIClient.meteorShowersRequest(
      coordinates: CLLocationCoordinate2D(latitude: 28.2916, longitude: -16.6291),
      baseURL: "https://server.oscars.love"
    )
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
      ($0.name, $0.value ?? "")
    })

    #expect(components.scheme == "https")
    #expect(components.host == "server.oscars.love")
    #expect(components.path == "/astro/meteors")
    #expect(query == ["lat": "28.292", "lon": "-16.629"])
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
  }

  @Test
  func requestUsesTheSharedOscarServerBaseURL() throws {
    let request = try APIClient.meteorShowersRequest(
      coordinates: CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405)
    )
    #expect(request.url?.absoluteString.hasPrefix(radarBaseURL + "/astro/meteors?") == true)
  }

  @Test
  func requestRejectsInvalidCoordinates() {
    for coordinates in [
      CLLocationCoordinate2D(latitude: .nan, longitude: 12),
      CLLocationCoordinate2D(latitude: 51, longitude: .infinity),
      CLLocationCoordinate2D(latitude: 91, longitude: 12),
      CLLocationCoordinate2D(latitude: 51, longitude: -181),
    ] {
      #expect(throws: URLError.self) {
        try APIClient.meteorShowersRequest(coordinates: coordinates)
      }
    }
  }
}

struct MeteorShowerNoticeTests {
  private static let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test(arguments: [-1_800.0, 0, 3_600])
  func noticeUsesWindowStartOrNowWhileOngoing(startOffset: Double) throws {
    let window = Self.window(start: Self.now.addingTimeInterval(startOffset))
    let notice = try #require(MeteorShowerForecast.notice(
      in: Self.response(window: window), now: Self.now
    ))

    #expect(notice.event.id == "PER")
    #expect(notice.date == max(window.start, Self.now))
  }

  @Test(arguments: ["good", "fair", "poor", "unknown"])
  func ratedConditionsKeepTheNotice(condition: String) {
    #expect(MeteorShowerForecast.notice(
      in: Self.response(condition: condition), now: Self.now
    ) != nil)
  }

  @Test(arguments: [0.0, -60])
  func endedWindowHasNoNotice(endOffset: Double) {
    let window = Self.window(
      start: Self.now.addingTimeInterval(-3_600),
      end: Self.now.addingTimeInterval(endOffset)
    )
    #expect(MeteorShowerForecast.notice(in: Self.response(window: window), now: Self.now) == nil)
  }

  @Test
  func unobservableLowActivityAndInconsistentResponsesHaveNoNotice() {
    let start = Self.now.addingTimeInterval(1_800)
    let responses = [
      Self.response(condition: "unobservable"),
      Self.response(condition: "poor", reasons: ["radiant_low", "low_activity"]),
      Self.response(window: Self.window(start: start, end: start)),
      MeteorShowerResponse(condition: "good", validUntil: Self.now),
      // The best window names a shower missing from the list.
      MeteorShowerResponse(
        condition: "good", bestWindow: Self.window(shower: "GEM"),
        showers: [MeteorShowerEvent(id: "PER", bestWindow: Self.window())],
        validUntil: Self.now
      ),
    ]
    for response in responses {
      #expect(MeteorShowerForecast.notice(in: response, now: Self.now) == nil)
    }
  }

  @Test
  func nearlyExpiredNowcastDoesNotHideAnUpcomingWindow() {
    let response = MeteorShowerResponse(
      condition: "good", bestWindow: Self.window(),
      showers: [MeteorShowerEvent(id: "PER", condition: "good", bestWindow: Self.window())],
      validUntil: Self.now.addingTimeInterval(-60)
    )
    #expect(MeteorShowerForecast.notice(in: response, now: Self.now)?.date == Self.window().start)
  }

  private static func window(
    shower: String = "PER",
    start: Date = now.addingTimeInterval(3_600),
    end: Date = now.addingTimeInterval(7_200)
  ) -> MeteorShowerWindow {
    MeteorShowerWindow(start: start, end: end, shower: shower, radiantAltitude: 60, moonIllumination: 0.1)
  }

  private static func response(
    window: MeteorShowerWindow = Self.window(),
    condition: String = "good",
    reasons: [String]? = nil
  ) -> MeteorShowerResponse {
    MeteorShowerResponse(
      condition: condition,
      bestWindow: window,
      showers: [MeteorShowerEvent(id: window.shower, condition: condition, bestWindow: window)],
      validUntil: window.end,
      reasons: reasons
    )
  }
}

struct MeteorShowerPhaseTests {
  private static let darknessStart = MeteorShowerDecodingTests.date("2026-08-12T21:00:00Z")
  private static let night = MeteorShowerNight(
    darknessStart: darknessStart,
    darknessEnd: darknessStart.addingTimeInterval(6 * 3_600),
    type: "astronomical"
  )

  @Test(arguments: [
    ("2026-08-13T00:00:00Z", MeteorShowerPhase.peakTonight),
    ("2026-08-13T12:00:00Z", .peakTonight),
    ("2026-08-12T12:00:00Z", .peakTonight),
    ("2026-08-13T12:00:01Z", .nearPeak),
    ("2026-08-14T12:00:00Z", .nearPeak),
    ("2026-08-11T12:00:00Z", .nearPeak),
    ("2026-08-14T12:00:01Z", .active),
    ("2026-07-31T12:00:00Z", .active),
  ] as [(String, MeteorShowerPhase)])
  func phaseIsMeasuredFromTheMiddleOfTheNight(peak: String, expected: MeteorShowerPhase) {
    let event = MeteorShowerEvent(id: "PER", peak: MeteorShowerDecodingTests.date(peak))
    #expect(MeteorShowerPhase.of(event, night: Self.night) == expected)
  }

  @Test
  func nightWithoutDarknessFallsBackToNow() {
    let now = MeteorShowerDecodingTests.date("2026-06-01T12:00:00Z")
    let event = MeteorShowerEvent(id: "ETA", peak: now.addingTimeInterval(20 * 3_600))
    #expect(MeteorShowerPhase.of(event, night: MeteorShowerNight(), now: now) == .nearPeak)
    #expect(MeteorShowerPhase.of(event, night: nil, now: now) == .nearPeak)
  }
}

struct MeteorShowerCopyTests {
  @Test
  func bannerCopyIsLocalizedPerPhase() {
    let german = Locale(identifier: "de")
    let english = Locale(identifier: "en")
    #expect(MeteorShowerCopy.bannerText(for: .peakTonight, locale: german) == "Sternschnuppen heute Nacht")
    #expect(MeteorShowerCopy.bannerText(for: .active, locale: german) == "Sternschnuppen aktiv")
    #expect(MeteorShowerCopy.bannerText(for: .active, locale: english) == "Shooting stars active")
    #expect(MeteorShowerCopy.detailPeakText(for: .peakTonight, locale: german) == "Heute Nacht")
    #expect(MeteorShowerCopy.detailPeakText(for: .nearPeak, locale: english) == "Near peak")
  }

  @Test
  func allCatalogueShowersHaveNamesAndRates() {
    let expectedGerman = [
      "QUA": "Quadrantiden",
      "LYR": "Lyriden",
      "ETA": "Eta-Aquariiden",
      "SDA": "Südliche Delta-Aquariiden",
      "PER": "Perseiden",
      "ORI": "Orioniden",
      "LEO": "Leoniden",
      "GEM": "Geminiden",
      "URS": "Ursiden",
    ]
    for (id, name) in expectedGerman {
      #expect(MeteorShowerCopy.showerName(for: id, locale: Locale(identifier: "de")) == name)
      #expect((MeteorShowerCatalogue.typicalZHR[id] ?? 0) > 0)
    }
    #expect(Set(MeteorShowerCatalogue.typicalZHR.keys) == Set(expectedGerman.keys))
    #expect(MeteorShowerCopy.showerName(for: "XYZ") == "XYZ")
  }

  @Test
  func weatherSourcesNameModelSatelliteAndRadar() {
    #expect(MeteorShowerCopy.weatherSourceNames(for: .init(source: "ecmwf")) == ["ECMWF"])
    #expect(MeteorShowerCopy.weatherSourceNames(
      for: .init(source: "meteosat-nowcast", precipitationSource: "opera-nowcast")
    ) == ["ECMWF", "EUMETSAT", "EUMETNET OPERA"])
    #expect(MeteorShowerCopy.weatherSourceNames(for: .init(source: "none")).isEmpty)
    #expect(MeteorShowerCopy.weatherSourceNames(
      for: .init(source: "future-model", precipitationSource: "future-radar")
    ).isEmpty)
  }
}

@MainActor
struct MeteorShowerStateTests {
  private static let coordinates = CLLocationCoordinate2D(latitude: 51.34, longitude: 12.38)

  @Test
  func primaryEventFollowsTheServersBestWindow() async {
    let weather = Weather()
    let window = MeteorShowerWindow(start: .now, end: .now.addingTimeInterval(3_600), shower: "PER")

    await weather.refreshMeteorShowers(coordinates: Self.coordinates) { coordinates in
      #expect(coordinates.latitude == 51.34)
      #expect(coordinates.longitude == 12.38)
      return MeteorShowerResponse(
        condition: "fair", bestWindow: window,
        showers: [MeteorShowerEvent(id: "SDA"), MeteorShowerEvent(id: "PER", bestWindow: window)],
        validUntil: window.end
      )
    }

    #expect(weather.meteorEvents.map(\.id) == ["SDA", "PER"])
    #expect(weather.primaryMeteorEvent?.id == "PER")
  }

  @Test
  func nightWithoutShowersIsNotRetained() async {
    let weather = Weather()
    await weather.refreshMeteorShowers(coordinates: Self.coordinates) { _ in
      MeteorShowerResponse(condition: "unobservable", validUntil: .now, reasons: ["no_active_shower"])
    }
    #expect(weather.meteorShowerResponse == nil)
    #expect(weather.primaryMeteorEvent == nil)
  }

  @Test
  func apiFailureDoesNotBreakNormalWeatherState() async {
    let weather = Weather()
    let updatedAt = Date(timeIntervalSince1970: 1_786_572_000)
    let temperature = weather.forecast.current?.temperature
    weather.lastUpdated = updatedAt
    weather.loadState = .loaded
    weather.error = "existing weather state"

    await weather.refreshMeteorShowers(coordinates: Self.coordinates) { _ in
      throw URLError(.notConnectedToInternet)
    }

    #expect(weather.error == "existing weather state")
    #expect(weather.lastUpdated == updatedAt)
    #expect(weather.forecast.current?.temperature == temperature)
    #expect(weather.meteorEvents.isEmpty)
    guard case .loaded = weather.loadState else {
      Issue.record("Meteor failure changed the normal weather load state")
      return
    }
  }

  @Test
  func newLocationFailureClearsPreviousCityEvent() async {
    let weather = Weather()
    let window = MeteorShowerWindow(start: .now, end: .now.addingTimeInterval(3_600), shower: "PER")

    await weather.refreshMeteorShowers(coordinates: Self.coordinates) { _ in
      MeteorShowerResponse(
        condition: "good", bestWindow: window,
        showers: [MeteorShowerEvent(id: "PER", bestWindow: window)], validUntil: window.end
      )
    }
    #expect(weather.primaryMeteorEvent?.id == "PER")

    await weather.refreshMeteorShowers(
      coordinates: CLLocationCoordinate2D(latitude: 28.2916, longitude: -16.6291)
    ) { _ in
      throw URLError(.timedOut)
    }

    #expect(weather.meteorEvents.isEmpty)
    #expect(weather.meteorShowerResponse == nil)
  }
}
