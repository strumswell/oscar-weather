//
//  ScreenshotFixtureServer.swift
//  Oscar°
//
//  URLProtocol fake server behind `-screenshotScene`: intercepts the forecast,
//  air-quality, alert, ensemble, archive, and notification endpoints on
//  URLSession.shared and answers from ScreenshotFixtures. oscar-server's radar
//  endpoints (frames, value grids, raster tiles, motion, cells, series) are
//  answered from SyntheticRadar so the map and widget scenes are deterministic.
//  Everything else (basemap tiles, colormaps) passes through untouched.
//

import Foundation
import HTTPTypes
import OpenAPIRuntime

final class ScreenshotFixtureServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard ScreenshotMode.active, let url = request.url else { return false }
        return route(for: url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let route = Self.route(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (body, contentType) = try route.respond(url)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Staged responses (non-URLProtocol paths)

    /// The fixture payload for a URL, or nil to let it hit the network.
    /// Backs the URLProtocol AND the APIClient staging seams — watchOS runs
    /// URLSession loading out of process, so URLProtocol never fires there.
    static func stagedResponse(for url: URL) -> (body: Data, contentType: String)? {
        guard ScreenshotMode.active, let route = route(for: url) else { return nil }
        return try? route.respond(url)
    }

    static func stagedFetch(_ request: URLRequest) -> (Data, HTTPURLResponse)? {
        guard let url = request.url, let staged = stagedResponse(for: url) else { return nil }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": staged.contentType]
        )!
        return (staged.body, response)
    }

    // MARK: - Routing

    private struct Route {
        let respond: (URL) throws -> (Data, String)
    }

    private static func json(_ make: @escaping (URL) -> Any) -> Route {
        Route { url in
            (try JSONSerialization.data(withJSONObject: make(url)), "application/json")
        }
    }

    private static func png(_ make: @escaping (URL) -> Data) -> Route {
        Route { url in (make(url), "image/png") }
    }

    private static func route(for url: URL) -> Route? {
        guard let host = url.host() else { return nil }
        let path = url.path()

        switch host {
        case "api.open-meteo.com" where path.hasPrefix("/v1/forecast"):
            return json { _ in ScreenshotFixtures.forecastJSON() }
        case "air-quality-api.open-meteo.com":
            return json { _ in ScreenshotFixtures.airQualityJSON() }
        case "api.brightsky.dev" where path.hasPrefix("/alerts"):
            return json { _ in ScreenshotFixtures.alertsJSON() }
        case "ensemble-api.open-meteo.com":
            return json { _ in ScreenshotFixtures.ensembleJSON() }
        case "archive-api.open-meteo.com":
            return json { url in ScreenshotFixtures.archiveJSON(for: url) }
        default:
            break
        }

        guard url.absoluteString.hasPrefix(radarBaseURL) else { return nil }

        if path.hasPrefix("/radar/series") {
            return json { _ in ScreenshotFixtures.precipSeriesJSON() }
        }
        // The notifications scene must never register against the real backend.
        if path.hasPrefix("/notifications") {
            return json { _ in
                ["subscriptionId": "screenshot-subscription", "apiKey": "screenshot-key"]
            }
        }

        // Synthetic radar: /radar/{region}[/precip-type]/frames[/{key}/(grid|tiles/z/x/y)]
        // plus /radar/{region}/(motion|cells). Colormaps and basemaps stay live.
        var parts = path.split(separator: "/").map(String.init)
        guard parts.first == "radar", parts.count >= 3 else { return nil }
        if parts[2] == "precip-type" { parts.remove(at: 2) }

        switch (parts.count, parts[2]) {
        case (3, "frames"):
            return json { _ in SyntheticRadar.framesJSON() }
        case (3, "motion"):
            return json { _ in SyntheticRadar.motionJSON() }
        case (3, "cells"):
            return json { _ in SyntheticRadar.cellsJSON() }
        case (5, "frames") where parts[4] == "grid":
            let key = parts[3]
            let typed = url.query()?.contains("style=typed") == true
            return png { _ in SyntheticRadar.gridPNG(frameKey: key, typed: typed) }
        case (8, "frames") where parts[4] == "tiles":
            let key = parts[3]
            guard let z = Int(parts[5]), let x = Int(parts[6]), let y = Int(parts[7]) else { return nil }
            return png { _ in SyntheticRadar.tilePNG(frameKey: key, z: z, x: x, y: y) }
        default:
            return nil
        }
    }
}

/// OpenAPI-client edition of the fixture server, prepended to every generated
/// client via `APIClient.stagingMiddlewares` (see there for the watchOS why).
struct ScreenshotFixtureMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Concatenate, don't resolve: request.path is relative to the server
        // URL, and URL(string:relativeTo:) would drop the base's own path
        // segment (e.g. the /v1 in api.open-meteo.com/v1).
        if let url = URL(string: baseURL.absoluteString + (request.path ?? "")),
           let staged = ScreenshotFixtureServer.stagedResponse(for: url) {
            var response = HTTPResponse(status: .ok)
            response.headerFields[.contentType] = staged.contentType
            return (response, HTTPBody(staged.body))
        }
        return try await next(request, body, baseURL)
    }
}
