//
//  ClimateArchiveService.swift
//  Oscar°
//
//  Persisted, unlimited cache of a location's raw daily-high history plus the in-process rate
//  limiter that protects the (very expensive) cold archive fetch. A cold location pulls ~85 years
//  of daily data in one request; thereafter we only ever fetch the missing recent days and merge
//  them in. App target only — the widget/watch targets never touch the climate timeline.
//

import Foundation
import OSLog

actor ClimateArchiveStore {
    static let shared = ClimateArchiveStore()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Climate"
    )

    private struct CacheEntry: Codable {
        var time: [String]
        var tmax: [Double?]
        var lastFetchDay: String
    }

    private let earliestDate = "1940-01-01"
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var memory: [String: CacheEntry] = [:]

    func dropMemory() {
        memory.removeAll()
    }

    private var fullCallTimestamps: [Date] = []
    private let maxFullCallsPerMinute = 2
    private let window: TimeInterval = 60

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("ClimateArchiveCache", isDirectory: true)
    }

    func summary(
        latitude: Double,
        longitude: Double,
        today: Date,
        todayHigh: Double?,
        onWaiting: @Sendable () -> Void
    ) async throws -> ClimateSummary? {
        let key = Self.locationKey(latitude: latitude, longitude: longitude)
        let todayStr = Self.dayString(today)
        var entry = loadEntry(key: key)

        if entry?.lastFetchDay != todayStr {
            if var existing = entry {
                let lastDay = existing.time.last ?? earliestDate
                let refreshStart = Self.dayString(
                    Calendar.current.date(byAdding: .day, value: -90, to: today) ?? today)
                let start = min(lastDay, refreshStart)
                do {
                    let fetched = try await fetch(
                        latitude: latitude, longitude: longitude, start: start, end: todayStr)
                    merge(into: &existing, time: fetched.time, tmax: fetched.tmax)
                    existing.lastFetchDay = todayStr
                    save(entry: existing, key: key)
                    entry = existing
                } catch {
                    Self.logger.error(
                        "Climate delta fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                try await acquireFullCallSlot(onWaiting: onWaiting)
                let fetched = try await fetch(
                    latitude: latitude, longitude: longitude, start: earliestDate, end: todayStr)
                var fresh = CacheEntry(
                    time: fetched.time, tmax: fetched.tmax, lastFetchDay: todayStr)
                trimTrailingNils(&fresh)
                save(entry: fresh, key: key)
                entry = fresh
            }
        }

        guard let entry, !entry.time.isEmpty else { return nil }
        return ClimateSummary.make(
            time: entry.time, tmax: entry.tmax, referenceDate: today, todayOverride: todayHigh)
    }

    // MARK: - Networking

    private func fetch(
        latitude: Double, longitude: Double, start: String, end: String
    ) async throws -> (time: [String], tmax: [Double?]) {
        let payload = try await APIClient.shared.getArchive(
            latitude: latitude, longitude: longitude, startDate: start, endDate: end)
        return (payload.daily?.time ?? [], payload.daily?.temperature_2m_max ?? [])
    }

    // MARK: - Rate limiting

    private func acquireFullCallSlot(onWaiting: @Sendable () -> Void) async throws {
        var notified = false
        while true {
            let now = Date()
            fullCallTimestamps.removeAll { now.timeIntervalSince($0) >= window }
            if fullCallTimestamps.count < maxFullCallsPerMinute {
                fullCallTimestamps.append(now)
                return
            }
            if !notified {
                onWaiting()
                notified = true
            }
            let oldest = fullCallTimestamps.min() ?? now
            let wait = max(window - now.timeIntervalSince(oldest) + 0.05, 0.1)
            try await Task.sleep(for: .seconds(wait))
        }
    }

    // MARK: - Merge helpers

    private func merge(into entry: inout CacheEntry, time: [String], tmax: [Double?]) {
        guard !time.isEmpty else { return }
        var map: [String: Double?] = [:]
        for (i, day) in entry.time.enumerated() where i < entry.tmax.count {
            map.updateValue(entry.tmax[i], forKey: day)
        }
        for (i, day) in time.enumerated() where i < tmax.count {
            if let incoming = tmax[i] {
                map.updateValue(incoming, forKey: day)
            } else if map.index(forKey: day) == nil {
                map.updateValue(nil, forKey: day)
            }
        }
        let sortedDays = map.keys.sorted()
        entry.time = sortedDays
        entry.tmax = sortedDays.map { map[$0] ?? nil }
        trimTrailingNils(&entry)
    }

    private func trimTrailingNils(_ entry: inout CacheEntry) {
        while let last = entry.tmax.last, last == nil {
            entry.tmax.removeLast()
            if !entry.time.isEmpty { entry.time.removeLast() }
        }
    }

    // MARK: - Persistence (unlimited, no TTL)

    private func loadEntry(key: String) -> CacheEntry? {
        if let cached = memory[key] { return cached }
        guard let data = try? Data(contentsOf: fileURL(key)),
            let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        memory[key] = entry
        return entry
    }

    private func save(entry: CacheEntry, key: String) {
        memory[key] = entry
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(entry).write(to: fileURL(key), options: .atomic)
        } catch {
            Self.logger.error(
                "Climate cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key.sha256Hex).json")
    }

    private static func locationKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
