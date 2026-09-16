import CryptoKit
import Foundation
import OSLog

actor DailyEnsembleForecastCache {
  static let shared = DailyEnsembleForecastCache()

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
    category: "Ensemble"
  )

  private struct Metadata: Codable {
    let key: String
    let timestamp: Date
  }

  private let lifetime: TimeInterval = 43_200
  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private var memoryCache: [String: (Date, Data)] = [:]
  private var sweptExpiredEntries = false

  func dropMemory() {
    memoryCache.removeAll()
  }

  private init() {
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    cacheDirectory = cachesDirectory.appendingPathComponent("DailyEnsembleAPICache", isDirectory: true)
  }

  func data(for key: String) -> Data? {
    let now = Date()

    if let (timestamp, data) = memoryCache[key], now.timeIntervalSince(timestamp) < lifetime {
      return data
    }

    let stem = fileStem(for: key)
    let metadataURL = cacheDirectory.appendingPathComponent("\(stem).json")
    let bodyURL = cacheDirectory.appendingPathComponent("\(stem).body")

    guard
      let metadataData = try? Data(contentsOf: metadataURL),
      let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData),
      now.timeIntervalSince(metadata.timestamp) < lifetime,
      let data = try? Data(contentsOf: bodyURL)
    else {
      try? fileManager.removeItem(at: metadataURL)
      try? fileManager.removeItem(at: bodyURL)
      memoryCache.removeValue(forKey: key)
      return nil
    }

    memoryCache[key] = (metadata.timestamp, data)
    return data
  }

  func set(_ data: Data, for key: String) {
    let timestamp = Date()
    memoryCache[key] = (timestamp, data)
    sweepExpiredEntriesOnce()

    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let stem = fileStem(for: key)
    let metadataURL = cacheDirectory.appendingPathComponent("\(stem).json")
    let bodyURL = cacheDirectory.appendingPathComponent("\(stem).body")
    let metadata = Metadata(key: key, timestamp: timestamp)

    do {
      try data.write(to: bodyURL, options: .atomic)
      try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
    } catch {
      Self.logger.error("Failed to write ensemble cache entry: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Entries expire only when their own key is read again, so each new city,
  /// model and unit combination would otherwise stay on disk forever.
  private func sweepExpiredEntriesOnce() {
    guard !sweptExpiredEntries else { return }
    sweptExpiredEntries = true
    guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
    let now = Date()
    for metadataURL in files where metadataURL.pathExtension == "json" {
      guard let metadataData = try? Data(contentsOf: metadataURL),
        let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData),
        now.timeIntervalSince(metadata.timestamp) >= lifetime
      else { continue }
      try? fileManager.removeItem(at: metadataURL)
      try? fileManager.removeItem(at: metadataURL.deletingPathExtension().appendingPathExtension("body"))
    }
  }

  private func fileStem(for key: String) -> String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
