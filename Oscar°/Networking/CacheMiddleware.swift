import Foundation
import HTTPTypes
import OpenAPIRuntime

actor CacheStore {
  private var cache: [String: (Date, HTTPResponse, Data)] = [:]
  private let userDefaults = UserDefaults.standard
  
  init() {
    Task {
      await loadFromPersistentStorage()
    }
  }

  func get(_ key: String) -> (Date, HTTPResponse, Data)? {
    return cache[key]
  }

  func set(_ key: String, value: (Date, HTTPResponse, Data)) {
    cache[key] = value
    saveToPersistentStorage(key: key, value: value)
    
    // Limit cache size to prevent unbounded growth
    if cache.count > 100 {
      cleanOldEntries()
    }
  }
  
  func clearCache() {
    cache.removeAll()
    userDefaults.removeObject(forKey: "APICache")
    print("Cache cleared")
  }
  
  private func cleanOldEntries() {
    let now = Date()
    let oldKeys = cache.compactMap { (key, value) in
      now.timeIntervalSince(value.0) > 604800 ? key : nil // Remove entries older than 1 week
    }
    
    if !oldKeys.isEmpty {
      for key in oldKeys {
        cache.removeValue(forKey: key)
      }
      
      // Update persistent storage
      var persistentCache = userDefaults.dictionary(forKey: "APICache") ?? [:]
      for key in oldKeys {
        persistentCache.removeValue(forKey: key)
      }
      userDefaults.set(persistentCache, forKey: "APICache")
      
      print("Cleaned \(oldKeys.count) old cache entries (older than 1 week)")
    }
  }
  
  private func loadFromPersistentStorage() {
    // Use UserDefaults dictionary instead of NSKeyedUnarchiver
    guard let cacheDict = userDefaults.dictionary(forKey: "APICache") else { return }
    
    let now = Date()
    var cleanedCache: [String: Any] = [:]
    var loadedCount = 0
    
    for (key, value) in cacheDict {
      guard let valueDict = value as? [String: Any],
            let timestampInterval = valueDict["timestamp"] as? TimeInterval,
            let statusCode = valueDict["statusCode"] as? Int,
            let dataString = valueDict["data"] as? String,
            let data = Data(base64Encoded: dataString) else { continue }
      
      let timestamp = Date(timeIntervalSince1970: timestampInterval)
      
      // Clean up entries older than 1 week
      if now.timeIntervalSince(timestamp) < 604800 { // 1 week (7 * 24 * 60 * 60)
        let response = HTTPResponse(status: HTTPResponse.Status(code: statusCode), headerFields: [:])
        cache[key] = (timestamp, response, data)
        cleanedCache[key] = value
        loadedCount += 1
      }
    }
    
    // Update UserDefaults with cleaned cache
    if cleanedCache.count < cacheDict.count {
      userDefaults.set(cleanedCache, forKey: "APICache")
      print("Cleaned \(cacheDict.count - cleanedCache.count) expired cache entries (older than 1 week)")
    }
    
    print("Loaded \(loadedCount) cached items from persistent storage")
  }
  
  private func saveToPersistentStorage(key: String, value: (Date, HTTPResponse, Data)) {
    var persistentCache = userDefaults.dictionary(forKey: "APICache") ?? [:]
    
    persistentCache[key] = [
      "timestamp": value.0.timeIntervalSince1970,
      "statusCode": value.1.status.code,
      "data": value.2.base64EncodedString()
    ]
    
    userDefaults.set(persistentCache, forKey: "APICache")
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
    return "\(baseURL.absoluteString)\(request.path ?? "")"
  }

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
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
