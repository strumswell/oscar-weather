//
//  ClimateArchiveService.swift
//  Oscar°
//
//  Persisted, unlimited cache of a location's raw daily-high history plus the in-process rate
//  limiter that protects the (very expensive) cold archive fetch. A cold location pulls ~85 years
//  of daily data in one request; thereafter we only ever fetch the missing recent days and merge
//  them in. App target only — the widget/watch targets never touch the climate timeline.
//

import CryptoKit
import Foundation
import OSLog

actor ClimateArchiveStore {
    static let shared = ClimateArchiveStore()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Climate"
    )

    /// What we persist per location: the full daily-high series plus the calendar day we last hit
    /// the network, so repeated views within a day never refetch.
    private struct CacheEntry: Codable {
        var time: [String]
        var tmax: [Double?]
        var lastFetchDay: String
    }

    private let earliestDate = "1940-01-01"
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var memory: [String: CacheEntry] = [:]

    // Rate limit: at most `maxFullCallsPerMinute` cold (no-cache) full-history fetches per rolling
    // minute. Warm delta fetches and cache hits are cheap and bypass it entirely. When the window
    // is exhausted a caller waits until a slot frees, then proceeds.
    private var fullCallTimestamps: [Date] = []
    private let maxFullCallsPerMinute = 2
    private let window: TimeInterval = 60

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("ClimateArchiveCache", isDirectory: true)
    }

    /// Reduced climate summary for a location. Serves from the persisted series when present,
    /// fetching only the missing recent days; a cold location triggers a full 1940→today fetch
    /// gated by the rate limiter, which invokes `onWaiting` while it blocks so the UI can show a
    /// spinner. The heavy reduction runs here, off the main actor.
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
                // Warm cache: refetch a rolling ~90-day trailing window (or further back, if the
                // cache is staler than that) through today, then merge. This serves two purposes:
                // it keeps the series gap-free no matter how long since the last touch, and it lets
                // final ERA5 values overwrite the preliminary ERA5T figures published for the most
                // recent months — so the cache self-heals toward the real reanalysis rather than
                // drifting. `min` (not `max`) guarantees we never start *after* the last stored day,
                // which would leave a hole. (`merge` prefers non-nil incoming values.)
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
                    // Offline / transient: keep the stale series rather than failing the section.
                    Self.logger.error(
                        "Climate delta fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            } else {
                // Cold location: the expensive call. Gate it behind the rate limiter.
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

    /// Merges a freshly fetched window into the stored series by date, preferring non-nil incoming
    /// values (so previously unavailable recent days get backfilled) and adding any new days.
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

    /// Drops trailing all-nil rows so "today" tracks the most recent day with real data.
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
        let stem = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(stem).json")
    }

    private static func locationKey(latitude: Double, longitude: Double) -> String {
        // The grid-snapped forecast coordinates are stable across refreshes; 2-decimal bucketing
        // (~1 km) absorbs any float jitter and maximizes reuse when revisiting a city.
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
