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

struct ContactIdentityMiddleware: ClientMiddleware {
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
