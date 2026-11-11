import Foundation
import Testing
@testable import Oscar_

struct WidgetCityTests {
    @Test(arguments: ["São Paulo, Centro", "Leipzig 🌧️", "Zürich,,_+/="])
    func madeIDRoundTripsNames(name: String) throws {
        let id = WidgetCity.makeID(latitude: -33.86882, longitude: -70.66927, name: name)
        let city = try #require(WidgetCity(id: id))
        #expect(city.id == id)
        #expect(city.name == name)
        #expect(city.latitude == -33.86882)
        #expect(city.longitude == -70.66927)
        #expect(city.isCurrentLocation == false)
    }

    @Test(arguments: zip([-33.86882, 51.3397, -0.00001], [151.20929, -12.3731, 0.0]))
    func madeIDRoundTripsCoordinates(latitude: Double, longitude: Double) throws {
        let city = try #require(WidgetCity(id: WidgetCity.makeID(latitude: latitude, longitude: longitude, name: "X")))
        #expect(city.latitude == latitude)
        #expect(city.longitude == longitude)
    }

    @Test
    func madeIDUsesSignedScaledCoordinates() {
        #expect(WidgetCity.makeID(latitude: -33.86882, longitude: 151.20929, name: "") == "city_m3386882_p15120929_")
    }

    @Test(arguments: ["current", "__current__"])
    func currentLocationIDsNormalizeToCurrent(id: String) throws {
        let city = try #require(WidgetCity(id: id))
        #expect(city.id == WidgetCity.currentLocationID)
        #expect(city.isCurrentLocation)
        #expect(city.latitude.isNaN)
        #expect(city.longitude.isNaN)
    }

    @Test
    func legacyCommaIDKeepsIDAndName() throws {
        let city = try #require(WidgetCity(id: "52.52,13.405,Berlin, Mitte"))
        #expect(city.id == "52.52,13.405,Berlin, Mitte")
        #expect(city.name == "Berlin, Mitte")
        #expect(city.latitude == 52.52)
        #expect(city.longitude == 13.405)
    }

    @Test
    func legacyCommaIDWithoutNameFallsBack() throws {
        let unnamed = try #require(WidgetCity(id: "-1.5,2"))
        let emptyName = try #require(WidgetCity(id: "-1.5,2,"))
        #expect(unnamed.latitude == -1.5)
        #expect(unnamed.longitude == 2)
        #expect(unnamed.name == emptyName.name)
        #expect(unnamed.name.isEmpty == false)
    }

    @Test
    func legacyCommaIDAcceptsNonFiniteCoordinates() throws {
        let city = try #require(WidgetCity(id: "nan,inf"))
        #expect(city.latitude.isNaN)
        #expect(city.longitude == .infinity)
    }

    @Test(arguments: ["", "Berlin", "52.52", "52.52;13.405", "abc,13.405", "city_x1_p1_QQ", "city_p1_p1_%%%", "city_p1_p1", "CURRENT"])
    func garbageIsRejected(id: String) {
        #expect(WidgetCity(id: id) == nil)
    }
}
