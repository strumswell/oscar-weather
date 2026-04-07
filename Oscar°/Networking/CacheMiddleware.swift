import Foundation
import CryptoKit
import HTTPTypes
import OpenAPIRuntime

actor CacheStore {
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
  private let maxEntryCount = 100
  private let persistentEntryLifetime: TimeInterval = 604800  // 1 week
  
  init() {
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    self.cacheDirectory = cachesDirectory.appendingPathComponent("APICache", isDirectory: true)
    self.cache = Self.loadFromPersistentStorage(
      cacheDirectory: cacheDirectory,
      fileManager: fileManager,
      persistentEntryLifetime: persistentEntryLifetime,
      maxEntryCount: maxEntryCount
    )
  }

  func get(_ key: String) -> (Date, HTTPResponse, Data)? {
    return cache[key]
  }

  func set(_ key: String, value: (Date, HTTPResponse, Data)) {
    cache[key] = value
    saveToPersistentStorage(key: key, value: value)
    
    // Limit cache size to prevent unbounded growth
    if cache.count > maxEntryCount {
      cleanOldEntries()
    }
  }
  
  func clearCache() {
    cache.removeAll()
    try? fileManager.removeItem(at: cacheDirectory)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    print("Cache cleared")
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

      print("Cleaned \(oldKeys.count) old cache entries (older than 1 week)")
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

      print("Cleaned \(overflowKeys.count) old cache entries (cache size limit)")
    }
  }
  
  private static func loadFromPersistentStorage(
    cacheDirectory: URL,
    fileManager: FileManager,
    persistentEntryLifetime: TimeInterval,
    maxEntryCount: Int
  ) -> [String: (Date, HTTPResponse, Data)] {
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    guard let metadataFiles = try? fileManager.contentsOfDirectory(
      at: cacheDirectory,
      includingPropertiesForKeys: nil
    ).filter({ $0.pathExtension == "json" }) else { return [:] }
    
    let now = Date()
    var loadedCache: [String: (Date, HTTPResponse, Data)] = [:]
    var loadedCount = 0
    var cleanedCount = 0
    
    for metadataURL in metadataFiles {
      guard let metadataData = try? Data(contentsOf: metadataURL),
            let metadata = try? JSONDecoder().decode(CachedResponseMetadata.self, from: metadataData)
      else { continue }

      if now.timeIntervalSince(metadata.timestamp) < persistentEntryLifetime {
        let fileStem = metadataURL.deletingPathExtension().lastPathComponent
        let bodyURL = bodyFileURL(forFileStem: fileStem, cacheDirectory: cacheDirectory)
        guard let data = try? Data(contentsOf: bodyURL) else {
          removePersistedFiles(fileStem: fileStem, cacheDirectory: cacheDirectory, fileManager: fileManager)
          cleanedCount += 1
          continue
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
        loadedCache[metadata.key] = (metadata.timestamp, response, data)
        loadedCount += 1
      } else {
        removePersistedFiles(
          fileStem: metadataURL.deletingPathExtension().lastPathComponent,
          cacheDirectory: cacheDirectory,
          fileManager: fileManager
        )
        cleanedCount += 1
      }
    }

    let overflowCount = loadedCache.count - maxEntryCount
    if overflowCount > 0 {
      let overflowKeys = loadedCache
        .sorted { $0.value.0 < $1.value.0 }
        .prefix(overflowCount)
        .map(\.key)

      for key in overflowKeys {
        loadedCache.removeValue(forKey: key)
        removePersistedFiles(
          fileStem: fileStem(for: key),
          cacheDirectory: cacheDirectory,
          fileManager: fileManager
        )
      }

      print("Cleaned \(overflowKeys.count) old cache entries (cache size limit)")
    }
    
    if cleanedCount > 0 {
      print("Cleaned \(cleanedCount) expired cache entries (older than 1 week)")
    }
    
    print("Loaded \(loadedCount) cached items from persistent storage")
    return loadedCache
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
      print("Failed to write API cache entry: \(error.localizedDescription)")
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

final class CachingMiddleware: ClientMiddleware {
  private let cacheTime: TimeInterval
  private let cacheStore: CacheStore

  init(cacheTime: TimeInterval = 10) {
    self.cacheTime = cacheTime
    self.cacheStore = CacheStore()
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

    // Check if we have a valid cached response
    if let (timestamp, cachedResponse, cachedData) = await cacheStore.get(key),
      Date().timeIntervalSince(timestamp) < cacheTime
    {
      print(" ---> Return cache for \(baseURL)")
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
          print("Create cache for \(baseURL)")
          return (response, HTTPBody(data))
        } catch {
          // If caching fails, still return the original response
          return (response, responseBody)
        }
      }

      return (response, responseBody)
    } catch {
      print("Error in CachingMiddleware: \(error.localizedDescription)")
      throw error
    }
  }
}
