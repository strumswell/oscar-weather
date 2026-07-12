import CoreLocation
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import Oscar_

struct WeatherSnapshotCoordinateTests {
    @Test
    func canonicalCoordinatesMatchSubPrecisionMovement() {
        let snapshot = CodableCoordinate(
            CLLocationCoordinate2D(latitude: 51.3397, longitude: 12.3731)
        )

        #expect(WeatherSnapshotStore.coordinatesMatch(
            snapshot: snapshot,
            current: CLLocationCoordinate2D(latitude: 51.33971, longitude: 12.37312)
        ))
    }

    @Test
    func nearbyButDifferentLocationDoesNotMatch() {
        let snapshot = CodableCoordinate(
            CLLocationCoordinate2D(latitude: 51.3397, longitude: 12.3731)
        )

        #expect(!WeatherSnapshotStore.coordinatesMatch(
            snapshot: snapshot,
            current: CLLocationCoordinate2D(latitude: 51.35, longitude: 12.38)
        ))
    }
}

struct PersistentCacheTests {
    @Test
    func staleResponseIsReturnedAfterNetworkFailure() async throws {
        let directory = try temporaryDirectory()
        let store = CacheStore(cacheDirectory: directory)
        let middleware = CachingMiddleware(cacheTime: -1, cacheStore: store)
        let request = HTTPRequest(
            method: .get,
            scheme: nil,
            authority: nil,
            path: "/forecast"
        )
        let baseURL = try #require(URL(string: "https://example.com"))

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "forecast"
        ) { _, _, _ in
            (HTTPResponse(status: .ok), HTTPBody(Data("last known good".utf8)))
        }

        let (_, fallbackBody) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "forecast"
        ) { _, _, _ in
            throw URLError(.notConnectedToInternet)
        }
        let fallbackData = try await Data(
            collecting: #require(fallbackBody),
            upTo: 1_024
        )
        #expect(String(decoding: fallbackData, as: UTF8.self) == "last known good")
    }

    @Test
    func staleResponseIsReturnedAfterServerFailure() async throws {
        let directory = try temporaryDirectory()
        let store = CacheStore(cacheDirectory: directory)
        let middleware = CachingMiddleware(cacheTime: -1, cacheStore: store)
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/forecast")
        let baseURL = try #require(URL(string: "https://example.com"))

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "forecast"
        ) { _, _, _ in
            (HTTPResponse(status: .ok), HTTPBody(Data("cached".utf8)))
        }

        let (response, fallbackBody) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "forecast"
        ) { _, _, _ in
            (HTTPResponse(status: .internalServerError), nil)
        }
        let fallbackData = try await Data(
            collecting: #require(fallbackBody),
            upTo: 1_024
        )
        #expect(response.status == .ok)
        #expect(String(decoding: fallbackData, as: UTF8.self) == "cached")
    }

    @Test
    func persistedResponseLoadsLazilyInANewStore() async throws {
        let directory = try temporaryDirectory()
        let firstStore = CacheStore(cacheDirectory: directory)
        let response = HTTPResponse(status: .ok)
        let body = Data("cached forecast".utf8)
        await firstStore.set("forecast-key", value: (.now, response, body))

        let relaunchedStore = CacheStore(cacheDirectory: directory)
        let cached = await relaunchedStore.get("forecast-key")

        #expect(cached?.1.status == .ok)
        #expect(cached?.2 == body)
    }

    @Test
    func expiredResponseIsRejectedAndRemoved() async throws {
        let directory = try temporaryDirectory()
        let writer = CacheStore(
            cacheDirectory: directory,
            persistentEntryLifetime: 1
        )
        await writer.set(
            "expired-key",
            value: (.now.addingTimeInterval(-60), HTTPResponse(status: .ok), Data("old".utf8))
        )

        let reader = CacheStore(
            cacheDirectory: directory,
            persistentEntryLifetime: 1
        )
        #expect(await reader.get("expired-key") == nil)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    @Test
    func corruptMetadataFailsSafely() async throws {
        let directory = try temporaryDirectory()
        let writer = CacheStore(cacheDirectory: directory)
        await writer.set(
            "corrupt-key",
            value: (.now, HTTPResponse(status: .ok), Data("body".utf8))
        )
        let metadata = try #require(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension == "json" })
        )
        try Data("not json".utf8).write(to: metadata, options: .atomic)

        let reader = CacheStore(cacheDirectory: directory)
        #expect(await reader.get("corrupt-key") == nil)
        #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
    }

    @Test
    func maintenanceKeepsOnlyNewestEntries() async throws {
        let directory = try temporaryDirectory()
        let store = CacheStore(cacheDirectory: directory, maxEntryCount: 2)
        let response = HTTPResponse(status: .ok)
        await store.set("oldest", value: (.now.addingTimeInterval(-30), response, Data("1".utf8)))
        await store.set("middle", value: (.now.addingTimeInterval(-20), response, Data("2".utf8)))
        await store.set("newest", value: (.now.addingTimeInterval(-10), response, Data("3".utf8)))
        await store.performPersistentMaintenance()

        let reader = CacheStore(cacheDirectory: directory, maxEntryCount: 2)
        #expect(await reader.get("oldest") == nil)
        #expect(await reader.get("middle") != nil)
        #expect(await reader.get("newest") != nil)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OscarOfflineCacheTests")
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
