// Routes Open-Meteo calls to the paid customer-*.open-meteo.com hosts, falling back to the free hosts on any failure.

import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Synchronization

enum OpenMeteoCustomer {
  static let apiKey: String? = {
    let key = Bundle.main.object(forInfoDictionaryKey: "OpenMeteoAPIKey") as? String ?? ""
    return key.isEmpty ? nil : key
  }()

  static let timeout: TimeInterval = 10
  private static let pauseDuration: TimeInterval = 5 * 60
  private static let pausedUntil = Mutex<[String: Date]>([:])
  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "OpenMeteoCustomer")

  static func customerVariant(of url: URL) -> URL? {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let host = components.host,
      host.hasSuffix(".open-meteo.com"), !host.hasPrefix("customer-")
    else { return nil }
    components.host = "customer-" + host
    return components.url
  }

  static func appendingKey(_ key: String, to pathOrURL: String) -> String {
    let encoded = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    return pathOrURL + (pathOrURL.contains("?") ? "&" : "?") + "apikey=" + encoded
  }

  static func isPaused(_ customerURL: URL) -> Bool {
    let host = customerURL.host() ?? ""
    return pausedUntil.withLock { ($0[host] ?? .distantPast) > .now }
  }

  static func pause(_ customerURL: URL) {
    let host = customerURL.host() ?? ""
    pausedUntil.withLock { $0[host] = .now + pauseDuration }
    logger.warning("\(host, privacy: .public) failed where the free host worked, pausing it")
  }

  static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let key = apiKey, let url = request.url,
      let customer = customerVariant(of: url), !isPaused(customer),
      let keyed = URL(string: appendingKey(key, to: customer.absoluteString))
    else { return try await URLSession.shared.data(for: request) }

    var customerRequest = request
    customerRequest.url = keyed
    customerRequest.timeoutInterval = timeout
    do {
      let (data, response) = try await URLSession.shared.data(for: customerRequest)
      if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
        return (data, response)
      }
    } catch {
      if isCancellation(error) { throw error }
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
      pause(customer)
    }
    return (data, response)
  }
}

nonisolated struct OpenMeteoCustomerMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard let key = OpenMeteoCustomer.apiKey,
      let customerBase = OpenMeteoCustomer.customerVariant(of: baseURL),
      !OpenMeteoCustomer.isPaused(customerBase)
    else { return try await next(request, body, baseURL) }

    var customerRequest = request
    customerRequest.path = OpenMeteoCustomer.appendingKey(key, to: request.path ?? "")
    do {
      let (response, responseBody) = try await next(customerRequest, body, customerBase)
      if response.status.kind == .successful { return (response, responseBody) }
    } catch {
      if OpenMeteoCustomer.isCancellation(error) { throw error }
    }

    let (response, responseBody) = try await next(request, body, baseURL)
    if response.status.kind == .successful { OpenMeteoCustomer.pause(customerBase) }
    return (response, responseBody)
  }
}
