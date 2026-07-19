import Foundation
import CryptoKit
import HTTPTypes
import OpenAPIRuntime
import OSLog

actor CacheStore {
  /// All API clients share one store: every instance points at the same on-disk
  /// `caches/APICache` directory, so separate stores each enforced their own
  /// eviction over shared files — one client could delete entries another still
  /// believed it held, and each reloaded the full directory at launch.
  static let shared = CacheStore()

  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Cache")

  private struct CachedResponseMetadata: Codable {
    struct Header: Codable {
      let name: String
      let value: String
    }

    let key: String
    let timestamp: Date
    let statusCode: Int
    let headers: [Header]
  }

  private var cache: [String: (Date, HTTPResponse, Data)] = [:]
  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private let maxEntryCount: Int
  private let persistentEntryLifetime: TimeInterval
  private var maintenanceScheduled = false
  private var hasPerformedPersistentMaintenance = false
  
  init(
    cacheDirectory: URL? = nil,
    persistentEntryLifetime: TimeInterval = 7 * 24 * 3_600,
    maxEntryCount: Int = 100
  ) {
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.cacheDirectory = cacheDirectory
      ?? cachesDirectory.appendingPathComponent("APICache", isDirectory: true)
    self.persistentEntryLifetime = persistentEntryLifetime
    self.maxEntryCount = maxEntryCount
    // Disk entries are loaded lazily by key. This keeps launch cheap while
    // preserving week-old last-known-good responses for offline fallback.
    self.cache = [:]
  }

  func get(_ key: String) -> (Date, HTTPResponse, Data)? {
    if let cached = cache[key] {
      return cached
    }
    guard let persisted = loadPersistedResponse(for: key) else { return nil }
    cache[key] = persisted
    return persisted
  }

  func set(_ key: String, value: (Date, HTTPResponse, Data)) {
    cache[key] = value
    saveToPersistentStorage(key: key, value: value)
    schedulePersistentMaintenanceIfNeeded()
    
    // Limit cache size to prevent unbounded growth
    if cache.count > maxEntryCount {
      cleanOldEntries()
    }
  }

  private func schedulePersistentMaintenanceIfNeeded() {
    guard !maintenanceScheduled, !hasPerformedPersistentMaintenance else { return }
    maintenanceScheduled = true
    Task(priority: .background) { [weak self] in
      await Task.yield()
      await self?.performPersistentMaintenance()
    }
  }

  func performPersistentMaintenance(now: Date = .now) {
    defer {
      maintenanceScheduled = false
      hasPerformedPersistentMaintenance = true
    }
    guard let files = try? fileManager.contentsOfDirectory(
      at: cacheDirectory,
      includingPropertiesForKeys: nil
    ) else { return }

    let metadataFiles = files.filter { $0.pathExtension == "json" }
    let bodyStems = Set(
      files.filter { $0.pathExtension == "body" }
        .map { $0.deletingPathExtension().lastPathComponent }
    )
    var validEntries: [(timestamp: Date, fileStem: String)] = []
    var metadataStems = Set<String>()

    for metadataURL in metadataFiles {
      let fileStem = metadataURL.deletingPathExtension().lastPathComponent
      metadataStems.insert(fileStem)
      guard let data = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(CachedResponseMetadata.self, from: data),
            now.timeIntervalSince(metadata.timestamp) < persistentEntryLifetime,
            bodyStems.contains(fileStem)
      else {
        removePersistedFiles(fileStem: fileStem)
        continue
      }
      validEntries.append((metadata.timestamp, fileStem))
    }

    for orphanedBodyStem in bodyStems.subtracting(metadataStems) {
      removePersistedFiles(fileStem: orphanedBodyStem)
    }

    let overflowCount = validEntries.count - maxEntryCount
    if overflowCount > 0 {
      for entry in validEntries.sorted(by: { $0.timestamp < $1.timestamp }).prefix(overflowCount) {
        cache = cache.filter { fileStem(for: $0.key) != entry.fileStem }
        removePersistedFiles(fileStem: entry.fileStem)
      }
    }
  }

  private func loadPersistedResponse(for key: String) -> (Date, HTTPResponse, Data)? {
    let fileStem = fileStem(for: key)
    let metadataURL = metadataFileURL(forFileStem: fileStem)
    guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
    guard let metadataData = try? Data(contentsOf: metadataURL),
          let metadata = try? JSONDecoder().decode(CachedResponseMetadata.self, from: metadataData),
          Date.now.timeIntervalSince(metadata.timestamp) < persistentEntryLifetime,
          let data = try? Data(contentsOf: bodyFileURL(forFileStem: fileStem))
    else {
      removePersistedFiles(fileStem: fileStem)
      return nil
    }

    var headers = HTTPFields()
    for header in metadata.headers {
      if let name = HTTPField.Name(header.name) {
        headers[name] = header.value
      }
    }
    let response = HTTPResponse(
      status: HTTPResponse.Status(code: metadata.statusCode),
      headerFields: headers
    )
    return (metadata.timestamp, response, data)
  }
  
  func clearCache() {
    cache.removeAll()
    try? fileManager.removeItem(at: cacheDirectory)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    Self.logger.debug("Cache cleared")
  }
  
  private func cleanOldEntries() {
    let now = Date()
    let oldKeys = cache.compactMap { (key, value) in
      now.timeIntervalSince(value.0) > persistentEntryLifetime ? key : nil
    }
    
    if !oldKeys.isEmpty {
      for key in oldKeys {
        cache.removeValue(forKey: key)
        removePersistedResponse(for: key)
      }

      Self.logger.debug("Cleaned \(oldKeys.count, privacy: .public) old cache entries (older than 1 week)")
    }

    let overflowCount = cache.count - maxEntryCount
    if overflowCount > 0 {
      let overflowKeys = cache
        .sorted { $0.value.0 < $1.value.0 }
        .prefix(overflowCount)
        .map(\.key)

      for key in overflowKeys {
        cache.removeValue(forKey: key)
        removePersistedResponse(for: key)
      }

      Self.logger.debug("Cleaned \(overflowKeys.count, privacy: .public) old cache entries (cache size limit)")
    }
  }

  private func saveToPersistentStorage(key: String, value: (Date, HTTPResponse, Data)) {
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let fileStem = fileStem(for: key)
    let metadata = CachedResponseMetadata(
      key: key,
      timestamp: value.0,
      statusCode: value.1.status.code,
      headers: value.1.headerFields.map {
        CachedResponseMetadata.Header(name: $0.name.rawName, value: $0.value)
      }
    )

    do {
      try value.2.write(to: bodyFileURL(forFileStem: fileStem), options: .atomic)
      let metadataData = try JSONEncoder().encode(metadata)
      try metadataData.write(to: metadataFileURL(forFileStem: fileStem), options: .atomic)
    } catch {
      Self.logger.error("Failed to write API cache entry: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func removePersistedResponse(for key: String) {
    removePersistedFiles(fileStem: fileStem(for: key))
  }

  private func removePersistedFiles(fileStem: String) {
    Self.removePersistedFiles(
      fileStem: fileStem,
      cacheDirectory: cacheDirectory,
      fileManager: fileManager
    )
  }

  private static func removePersistedFiles(
    fileStem: String,
    cacheDirectory: URL,
    fileManager: FileManager
  ) {
    try? fileManager.removeItem(at: metadataFileURL(forFileStem: fileStem, cacheDirectory: cacheDirectory))
    try? fileManager.removeItem(at: bodyFileURL(forFileStem: fileStem, cacheDirectory: cacheDirectory))
  }

  private func metadataFileURL(forFileStem fileStem: String) -> URL {
    Self.metadataFileURL(forFileStem: fileStem, cacheDirectory: cacheDirectory)
  }

  private static func metadataFileURL(forFileStem fileStem: String, cacheDirectory: URL) -> URL {
    cacheDirectory.appendingPathComponent("\(fileStem).json")
  }

  private func bodyFileURL(forFileStem fileStem: String) -> URL {
    Self.bodyFileURL(forFileStem: fileStem, cacheDirectory: cacheDirectory)
  }

  private static func bodyFileURL(forFileStem fileStem: String, cacheDirectory: URL) -> URL {
    cacheDirectory.appendingPathComponent("\(fileStem).body")
  }

  private func fileStem(for key: String) -> String {
    Self.fileStem(for: key)
  }

  private static func fileStem(for key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

nonisolated final class CachingMiddleware: ClientMiddleware {
  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Cache")
  private let cacheTime: TimeInterval
  private let cacheStore: CacheStore

  init(cacheTime: TimeInterval = 10, cacheStore: CacheStore = .shared) {
    self.cacheTime = cacheTime
    self.cacheStore = cacheStore
  }
  
  func clearCache() async {
    await cacheStore.clearCache()
  }

  private func cacheKey(for request: HTTPRequest, baseURL: URL) -> String {
    return "\(request.method.rawValue) \(canonicalURL(for: request, baseURL: baseURL))"
  }

  private func canonicalURL(for request: HTTPRequest, baseURL: URL) -> String {
    guard let path = request.path,
          let url = URL(string: path, relativeTo: baseURL),
          var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    else {
      return "\(baseURL.absoluteString)\(request.path ?? "")"
    }

    components.queryItems = components.queryItems?
      .map { item in
        URLQueryItem(name: item.name, value: canonicalQueryValue(item.value, for: item.name))
      }
      .sorted {
        if $0.name == $1.name {
          return ($0.value ?? "") < ($1.value ?? "")
        }
        return $0.name < $1.name
      }

    return components.url?.absoluteString ?? "\(baseURL.absoluteString)\(path)"
  }

  private func canonicalQueryValue(_ value: String?, for name: String) -> String? {
    guard let value, Self.coordinateQueryNames.contains(name.lowercased()),
          let coordinate = Double(value) else {
      return value
    }

    return String(
      format: "%.\(LocationService.outboundCoordinateDecimalPlaces)f",
      LocationService.roundedOutboundCoordinate(coordinate)
    )
  }

  private static let coordinateQueryNames: Set<String> = ["lat", "lon", "latitude", "longitude"]

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard request.method == .get else {
      return try await next(request, body, baseURL)
    }

    let key = cacheKey(for: request, baseURL: baseURL)

    let cached = await cacheStore.get(key)

    // Fresh entries avoid the request entirely. Older persisted entries stay
    // available below as last-known-good data if the network/server fails.
    if let (timestamp, cachedResponse, cachedData) = cached,
      Date.now.timeIntervalSince(timestamp) < cacheTime
    {
      Self.logger.debug(" ---> Return cache for \(baseURL, privacy: .public)")
      return (cachedResponse, HTTPBody(cachedData))
    }

    // If not cached or expired, perform the request
    do {
      let (response, responseBody) = try await next(request, body, baseURL)

      // Cache only successful responses (2xx status codes)
      if (200...299).contains(response.status.code), let responseBody = responseBody {
        do {
          let data = try await Data(collecting: responseBody, upTo: 10 * 1024 * 1024)  // 10 MB limit
          await cacheStore.set(key, value: (Date(), response, data))
          Self.logger.debug("Create cache for \(baseURL, privacy: .public)")
          return (response, HTTPBody(data))
        } catch {
          // `responseBody` is a single-pass stream that the failed collect may have already
          // partially consumed, so it can't be safely returned. Surface the error rather than
          // handing a truncated body to the decoder.
          throw error
        }
      }

      if let (_, cachedResponse, cachedData) = cached {
        Self.logger.info(" ---> Return stale cache after HTTP \(response.status.code, privacy: .public) for \(baseURL, privacy: .public)")
        return (cachedResponse, HTTPBody(cachedData))
      }
      return (response, responseBody)
    } catch {
      if let (_, cachedResponse, cachedData) = cached {
        Self.logger.info(" ---> Return stale cache after network failure for \(baseURL, privacy: .public)")
        return (cachedResponse, HTTPBody(cachedData))
      }
      Self.logger.error("Error in CachingMiddleware: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }
}
