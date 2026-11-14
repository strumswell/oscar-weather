import CoreLocation
import Testing
@testable import Oscar_

struct GeocodeLocationDisplayTests {
    @Test
    func detailLineSkipsTheNameAndEmptyParts() {
        var location = Components.Schemas.Location()
        location.name = "Leipzig"
        location.admin3 = "Leipzig"
        location.admin1 = "Sachsen"
        location.country = "Deutschland"

        #expect(location.detailLine == "Sachsen, Deutschland")
        #expect(location.displayName == "Leipzig")
    }

    @Test
    func detailLineIsNilWithoutRegionData() {
        var location = Components.Schemas.Location()
        location.name = "Nowhere"

        #expect(location.detailLine == nil)
    }

    @Test
    func flagEmojiComesFromTheCountryCode() {
        var location = Components.Schemas.Location()
        location.country_code = "de"
        #expect(location.flagEmoji == "🇩🇪")

        location.country_code = "TR"
        #expect(location.flagEmoji == "🇹🇷")

        location.country_code = "XYZ"
        #expect(location.flagEmoji == nil)
    }

    @Test
    func notificationPlacePrefersStoredCityThenGPSThenSelected() {
        let leipzig = CLLocationCoordinate2D(latitude: 51.34, longitude: 12.37)
        let hessen = CLLocationCoordinate2D(latitude: 52.01, longitude: 10.78)
        let deleted = CLLocationCoordinate2D(latitude: 48.14, longitude: 11.58)
        let cities = [leipzig, hessen]
        let resolve = NotificationSettingsManager.resolveNotificationPlace

        #expect(resolve(hessen, cities, true, 0) == .city(1))
        #expect(resolve(hessen, cities, false, 0) == .city(1))
        #expect(resolve(deleted, cities, true, 0) == .currentLocation)
        #expect(resolve(nil, cities, true, 0) == .currentLocation)
        #expect(resolve(deleted, cities, false, 0) == .city(0))
        #expect(resolve(nil, cities, false, nil) == nil)
        #expect(resolve(nil, [], false, nil) == nil)
    }
}
