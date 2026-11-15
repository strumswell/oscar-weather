// Last-good copies of widget API payloads in the app group, used when a fetch fails.
import CoreLocation
import Foundation

enum WidgetCache {
    private struct Stored<Value: Codable>: Codable {
        let fetchedAt: Date
        let value: Value
    }

    static func key(_ kind: String, _ coordinates: CLLocationCoordinate2D) -> String {
        String(format: "%@_%.2f_%.2f", kind, coordinates.latitude, coordinates.longitude)
    }

    static func fetch<T: Codable & Sendable>(
        _ key: String,
        maxAge: TimeInterval = 0,
        maxStale: TimeInterval = .infinity,
        fetch: () async throws -> T
    ) async throws -> (value: T, fetchedAt: Date) {
        let file = directory.appending(path: "\(key).json")
        if maxAge > 0, let stored = load(T.self, from: file), Date().timeIntervalSince(stored.fetchedAt) < maxAge {
            return (stored.value, stored.fetchedAt)
        }
        do {
            let value = try await fetch()
            let now = Date()
            if let data = try? JSONEncoder().encode(Stored(fetchedAt: now, value: value)) {
                try? data.write(to: file, options: .atomic)
            }
            return (value, now)
        } catch {
            guard let stored = load(T.self, from: file), Date().timeIntervalSince(stored.fetchedAt) < maxStale else { throw error }
            return (stored.value, stored.fetchedAt)
        }
    }

    static func cached<T: Codable>(_ key: String) -> T? {
        load(T.self, from: directory.appending(path: "\(key).json"))?.value
    }

    private static func load<T: Codable>(_ type: T.Type, from file: URL) -> Stored<T>? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Stored<T>.self, from: data)
    }

    private static let directory: URL = {
        let manager = FileManager.default
        let base = manager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) ?? .cachesDirectory
        let directory = base.appending(path: "WidgetCache", directoryHint: .isDirectory)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff {
                try? manager.removeItem(at: file)
            }
        }
        return directory
    }()
}
