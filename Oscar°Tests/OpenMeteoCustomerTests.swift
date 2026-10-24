import Foundation
import Testing
@testable import Oscar_

struct OpenMeteoCustomerTests {
    @Test(arguments: ["api", "air-quality-api", "geocoding-api", "archive-api", "ensemble-api"])
    func everyOpenMeteoHostGetsItsCustomerVariant(_ prefix: String) throws {
        let url = try #require(URL(string: "https://\(prefix).open-meteo.com/v1/x?latitude=1"))
        #expect(OpenMeteoCustomer.customerVariant(of: url)?.absoluteString
            == "https://customer-\(prefix).open-meteo.com/v1/x?latitude=1")
    }

    @Test
    func basePathSurvivesAndOtherHostsStayUntouched() throws {
        let geocoding = try #require(URL(string: "https://geocoding-api.open-meteo.com/v1"))
        #expect(OpenMeteoCustomer.customerVariant(of: geocoding)?.absoluteString
            == "https://customer-geocoding-api.open-meteo.com/v1")
        let oscarServer = try #require(URL(string: "https://server.oscars.love/radar"))
        let alreadyCustomer = try #require(URL(string: "https://customer-api.open-meteo.com"))
        #expect(OpenMeteoCustomer.customerVariant(of: oscarServer) == nil)
        #expect(OpenMeteoCustomer.customerVariant(of: alreadyCustomer) == nil)
    }

    @Test
    func keyIsAppendedAsQueryItem() {
        #expect(OpenMeteoCustomer.appendingKey("abc", to: "/v1/forecast?latitude=1") == "/v1/forecast?latitude=1&apikey=abc")
        #expect(OpenMeteoCustomer.appendingKey("a+b", to: "/search") == "/search?apikey=a%2Bb")
    }
}
