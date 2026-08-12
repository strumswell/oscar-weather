import Foundation
import CoreLocation
import Testing
@testable import Oscar_

struct MeteorShowerDecodingTests {
  @Test
  func decodesActiveResponseAndIgnoresUnknownFields() throws {
    let response = try MeteorShowerResponse.decode(from: Data(Self.activeResponse.utf8))

    #expect(response.supported)
    #expect(response.location?.countryCode == "ES")
    #expect(response.location?.timezone == "Atlantic/Canary")
    #expect(response.localDate == "2026-08-12")
    #expect(response.night?.darknessDurationHours == 7.96)
    #expect(response.night?.darknessStart != nil)
    #expect(response.events.count == 1)
    #expect(response.events[0].id == "PER")
    #expect(response.events[0].zhr == 100)
    #expect(response.events[0].peakEnd != nil)
    #expect(response.events[0].visibility.classification == "excellent")
    #expect(response.events[0].radiant.dec == 58)
  }

  @Test
  func decodesEmptyEvents() throws {
    let response = try MeteorShowerResponse.decode(from: Data(
      Self.emptySupportedResponse.utf8
    ))

    #expect(response.supported)
    #expect(response.events.isEmpty)
    #expect(response.location?.countryCode == "DE")
    #expect(response.night?.darknessType == "none")
  }

  @Test
  func rejectsIncompleteSupportedResponseAndMalformedEvent() {
    #expect(throws: DecodingError.self) {
      try MeteorShowerResponse.decode(from: Data(
        #"{"supported":true,"events":[]}"#.utf8
      ))
    }
    #expect(throws: DecodingError.self) {
      try MeteorShowerResponse.decode(from: Data(
        Self.activeResponse.replacingOccurrences(of: #""zhr": 100,"#, with: "")
          .utf8
      ))
    }
  }

  private static let emptySupportedResponse = #"""
  {
    "supported": true,
    "location": {
      "latitude": 51.34,
      "longitude": 12.38,
      "country_code": "DE",
      "timezone": "Europe/Berlin"
    },
    "local_date": "2026-08-12",
    "night": {
      "sunset": null,
      "sunrise": null,
      "darkness_start": null,
      "darkness_end": null,
      "darkness_type": "none",
      "darkness_duration_hours": 0
    },
    "events": []
  }
  """#

  @Test
  func decodesUnsupportedResponse() throws {
    let response = try MeteorShowerResponse.decode(from: Data(
      #"{"supported":false,"events":[]}"#.utf8
    ))

    #expect(!response.supported)
    #expect(response.events.isEmpty)
  }

  private static let activeResponse = #"""
  {
    "supported": true,
    "location": {
      "latitude": 28.2916,
      "longitude": -16.6291,
      "country_code": "ES",
      "timezone": "Atlantic/Canary",
      "future_location_field": "ignored"
    },
    "local_date": "2026-08-12",
    "night": {
      "sunset": "2026-08-12T20:48:06+01:00",
      "sunrise": "2026-08-13T07:35:08+01:00",
      "darkness_start": "2026-08-12T22:12:44+01:00",
      "darkness_end": "2026-08-13T06:10:30+01:00",
      "darkness_type": "astronomical",
      "darkness_duration_hours": 7.96
    },
    "events": [
      {
        "id": "PER",
        "name": "Perseids",
        "status": "peak",
        "presentation": "many_tonight",
        "zhr": 100,
        "peak": "2026-08-13T02:00:00Z",
        "peak_end": "2026-08-13T04:00:00.125Z",
        "peak_precision": "window",
        "visibility": {
          "classification": "excellent",
          "observable": true,
          "radiant_rises": true,
          "radiant_visible": true,
          "max_radiant_altitude": 55.5,
          "best_time": "2026-08-13T06:10:30+01:00",
          "future_visibility_field": 42
        },
        "radiant": {
          "ra": 48.0,
          "dec": 58.0
        },
        "source": "IMO",
        "future_event_field": {"ignored": true}
      }
    ],
    "future_root_field": [1, 2, 3]
  }
  """#
}

struct MeteorShowerCopyTests {
  @Test
  func manyTonightUsesRequestedGermanAndEnglishCopy() {
    #expect(MeteorShowerCopy.bannerText(
      for: "many_tonight", locale: Locale(identifier: "de")
    ) == "Heute Nacht viele Sternschnuppen möglich")
    #expect(MeteorShowerCopy.bannerText(
      for: "many_tonight", locale: Locale(identifier: "en")
    ) == "Many shooting stars possible tonight")
    #expect(MeteorShowerCopy.bannerText(
      for: "active", locale: Locale(identifier: "de")
    ) == "Sternschnuppen aktiv")
    #expect(MeteorShowerCopy.bannerText(
      for: "active", locale: Locale(identifier: "en")
    ) == "Shooting stars active")
  }

  @Test
  func visibilityClassificationsAreLocalized() {
    let expectedGerman = [
      "not_visible": "Nicht sichtbar",
      "poor": "Schlecht",
      "fair": "Mäßig",
      "good": "Gut",
      "excellent": "Ausgezeichnet",
    ]
    let expectedEnglish = [
      "not_visible": "Not visible",
      "poor": "Poor",
      "fair": "Fair",
      "good": "Good",
      "excellent": "Excellent",
    ]

    for (value, expected) in expectedGerman {
      #expect(MeteorShowerCopy.visibilityText(
        for: value, locale: Locale(identifier: "de")
      ) == expected)
    }
    for (value, expected) in expectedEnglish {
      #expect(MeteorShowerCopy.visibilityText(
        for: value, locale: Locale(identifier: "en")
      ) == expected)
    }
    #expect(MeteorShowerCopy.visibilityText(for: "future_value") == nil)
  }

  @Test
  func allCatalogueShowerNamesUseStableIDs() {
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
      let event = MeteorShowerEvent(id: id, name: "Backend name")
      #expect(MeteorShowerCopy.showerName(
        for: event,
        locale: Locale(identifier: "de")
      ) == name)
    }
  }
}

struct MeteorShowerRequestTests {
  @Test
  func requestRoundsCoordinatesAndNormalizesCountryCode() throws {
    let request = try APIClient.activeMeteorShowersRequest(
      coordinates: CLLocationCoordinate2D(latitude: 28.2916, longitude: -16.6291),
      countryCode: " es "
    )
    let url = try #require(request.url)
    let components = try #require(URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    ))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
      ($0.name, $0.value ?? "")
    })

    #expect(query["lat"] == "28.292")
    #expect(query["lon"] == "-16.629")
    #expect(query["country_code"] == "ES")
  }
}

struct MeteorShowerForecastTests {
  @Test
  func cloudCoverUsesNearestObservingHourAndAlignedValues() {
    let observingTime = Date(timeIntervalSince1970: 7_100)
    #expect(MeteorShowerForecast.cloudCover(
      nearestTo: observingTime,
      timestamps: [3_600, 7_200, 10_800],
      values: [90, 25, 70]
    ) == 25)
    #expect(MeteorShowerForecast.cloudCover(
      nearestTo: observingTime,
      timestamps: [3_600, 7_200],
      values: []
    ) == nil)
  }
}

struct MeteorShowerEventSelectionTests {
  @Test
  func presentationPriorityWinsBeforeZHRAndZHRBreaksSamePriorityTies() throws {
    let many = MeteorShowerEvent(
      id: "MANY", name: "Many", presentation: "many_tonight", zhr: 5
    )
    let peak = MeteorShowerEvent(
      id: "PEAK", name: "Peak", presentation: "peak_tonight", zhr: 500
    )
    let selectedByPresentation = try #require(
      MeteorShowerEventSelector.select(from: [peak, many])
    )
    #expect(selectedByPresentation.id == "MANY")

    let weaker = MeteorShowerEvent(
      id: "WEAK", name: "Weak", presentation: "near_peak", zhr: 10
    )
    let stronger = MeteorShowerEvent(
      id: "STRONG", name: "Strong", presentation: "near_peak", zhr: 40
    )
    let selectedByZHR = try #require(
      MeteorShowerEventSelector.select(from: [weaker, stronger])
    )
    #expect(selectedByZHR.id == "STRONG")

    let alpha = MeteorShowerEvent(
      id: "A", name: "Alpha", presentation: "active", zhr: 10
    )
    let beta = MeteorShowerEvent(
      id: "B", name: "Beta", presentation: "active", zhr: 10
    )
    let selectedByID = try #require(
      MeteorShowerEventSelector.select(from: [beta, alpha])
    )
    #expect(selectedByID.id == "A")
  }
}

@MainActor
struct MeteorShowerStateTests {
  @Test
  func apiFailureDoesNotBreakNormalWeatherState() async {
    let weather = Weather()
    let updatedAt = Date(timeIntervalSince1970: 1_786_572_000)
    let temperature = weather.forecast.current?.temperature
    weather.lastUpdated = updatedAt
    weather.loadState = .loaded
    weather.error = "existing weather state"

    await weather.refreshMeteorShowers(
      coordinates: CLLocationCoordinate2D(latitude: 28.2916, longitude: -16.6291),
      countryCode: "ES"
    ) { _, _ in
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
    let oldEvent = MeteorShowerEvent(
      id: "OLD", name: "Old city shower", presentation: "active", zhr: 10
    )

    await weather.refreshMeteorShowers(
      coordinates: CLLocationCoordinate2D(latitude: 51.34, longitude: 12.38),
      countryCode: "de"
    ) { coordinates, countryCode in
      #expect(coordinates.latitude == 51.34)
      #expect(coordinates.longitude == 12.38)
      #expect(countryCode == "DE")
      return MeteorShowerResponse(supported: true, events: [oldEvent])
    }
    #expect(weather.primaryMeteorEvent?.id == "OLD")

    await weather.refreshMeteorShowers(
      coordinates: CLLocationCoordinate2D(latitude: 28.2916, longitude: -16.6291),
      countryCode: "es"
    ) { coordinates, countryCode in
      #expect(coordinates.latitude == 28.2916)
      #expect(coordinates.longitude == -16.6291)
      #expect(countryCode == "ES")
      throw URLError(.timedOut)
    }

    #expect(weather.meteorEvents.isEmpty)
    #expect(weather.meteorShowerResponse == nil)
  }
}
