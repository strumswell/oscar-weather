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

nonisolated struct UsageCountingMiddleware: ClientMiddleware {
  nonisolated(unsafe) static var onRequest: (@Sendable (_ host: String) -> Void)?

  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    Self.onRequest?(Self.key(host: baseURL.host() ?? "unknown", operationID: operationID))
    return try await next(request, body, baseURL)
  }

  static func key(host: String, operationID: String) -> String {
    guard host.hasSuffix("oscars.love") else { return host }
    let area =
      switch operationID {
      case let id where id.hasPrefix("getRadar"): "radar"
      case let id where id.hasPrefix("getCloud"): "clouds"
      case let id where id.hasPrefix("getModel"): "layers"
      case "getWindField", "getColormap": "layers"
      case "getOscarPointAlerts": "alerts"
      case "getNearbyStations": "stations"
      case "getWebcams": "webcams"
      case let id where id.contains("otification") || id.contains("LiveActivity"): "notifications"
      default: "other"
      }
    return "\(host)/\(area)"
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
