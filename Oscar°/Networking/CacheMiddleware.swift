import Foundation
import HTTPTypes
import OpenAPIRuntime

actor CacheStore {
  private var cache: [String: (Date, HTTPResponse, Data)] = [:]

  func get(_ key: String) -> (Date, HTTPResponse, Data)? {
    return cache[key]
  }

  func set(_ key: String, value: (Date, HTTPResponse, Data)) {
    cache[key] = value
  }
}

final class CachingMiddleware: ClientMiddleware {
  private let cacheTime: TimeInterval
  private let cacheStore: CacheStore

  init(cacheTime: TimeInterval = 10) {
    self.cacheTime = cacheTime
    self.cacheStore = CacheStore()
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
