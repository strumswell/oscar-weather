import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import Oscar_

struct ForecastSanitizingMiddlewareTests {
    private let body = """
    {"hourly":{"time":[1,2,3],"temperature_2m":[10.5,null,12.0]},"hourly_units":{"temperature_2m":"undefined"}}
    """

    private func intercept(path: String) async throws -> [String: Any] {
        let middleware = ForecastSanitizingMiddleware()
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: path)
        let baseURL = try #require(URL(string: "https://example.com"))
        let (_, responseBody) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "getForecast"
        ) { _, _, _ in
            (HTTPResponse(status: .ok), HTTPBody(Data(body.utf8)))
        }
        let data = try await Data(collecting: #require(responseBody), upTo: 1_024 * 1_024)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func forcedModelSeriesAreCutAtTheFirstNull() async throws {
        let root = try await intercept(path: "/v1/forecast?models=icon_seamless&temperature_unit=fahrenheit")
        let hourly = try #require(root["hourly"] as? [String: Any])
        #expect((hourly["time"] as? [Any])?.count == 1)
        #expect((hourly["temperature_2m"] as? [Any])?.count == 1)
        let units = try #require(root["hourly_units"] as? [String: Any])
        #expect(units["temperature_2m"] as? String == "°F")
    }

    @Test
    func bestMatchBodiesPassThroughUntouched() async throws {
        let root = try await intercept(path: "/v1/forecast?models=best_match")
        let hourly = try #require(root["hourly"] as? [String: Any])
        #expect((hourly["time"] as? [Any])?.count == 3)
        #expect((hourly["temperature_2m"] as? [Any])?.contains { $0 is NSNull } == true)
    }
}
