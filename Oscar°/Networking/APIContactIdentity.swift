import Foundation
import HTTPTypes
import OpenAPIRuntime

enum APIContactIdentity {
  static let contactEmail = "oscar@bolte.id"

  static var userAgent: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let versionSuffix = version.map { "/\($0)" } ?? ""
    return "OscarWeather\(versionSuffix) (non-commercial OSS; +https://bolte.id; mailto:\(contactEmail))"
  }

  static func apply(to request: inout HTTPRequest) {
    request.headerFields[.userAgent] = userAgent
    request.headerFields[.from] = contactEmail
  }

  static func apply(to request: inout URLRequest) {
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue(contactEmail, forHTTPHeaderField: "From")
  }
}

extension URLRequest {
  mutating func addAPIContactIdentity() {
    APIContactIdentity.apply(to: &self)
  }
}

/// Counts network requests per host for the usage statistics. Placed behind
/// `CachingMiddleware`, so cache hits stay uncounted; retries sit inside it
/// and count once. Widgets and the watch never set the hook and count nothing.
nonisolated struct UsageCountingMiddleware: ClientMiddleware {
  nonisolated(unsafe) static var onRequest: (@Sendable (_ host: String) -> Void)?

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    Self.onRequest?(baseURL.host() ?? "unknown")
    return try await next(request, body, baseURL)
  }
}

nonisolated struct ContactIdentityMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var request = request
    APIContactIdentity.apply(to: &request)
    return try await next(request, body, baseURL)
  }
}
