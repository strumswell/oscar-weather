//
//  RetryClientMiddleware.swift
//  Oscar°
//
//  Created by Philipp Bolte on 22.01.24.
//

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftOpenAPIGenerator open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftOpenAPIGenerator project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftOpenAPIGenerator project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OSLog

nonisolated struct RetryingMiddleware {

  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Retry")

  enum RetryableSignal: Hashable {

    case code(Int)

    case range(Range<Int>)

    case errorThrown
  }

  enum RetryingPolicy: Hashable {

    case never

    case upToAttempts(count: Int)
  }

  enum DelayPolicy: Hashable {

    case none

    case constant(seconds: TimeInterval)

    case exponentialWithJitter(base: TimeInterval, maxSeconds: TimeInterval)
  }

  var signals: Set<RetryableSignal>

  var policy: RetryingPolicy

  var delay: DelayPolicy

  init(
    signals: Set<RetryableSignal> = [.code(429), .range(500..<600), .errorThrown],
    policy: RetryingPolicy = .upToAttempts(count: 3),
    delay: DelayPolicy = .constant(seconds: 1)
  ) {
    self.signals = signals
    self.policy = policy
    self.delay = delay
  }
}

extension RetryingMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    let requestContext = "\(baseURL.host() ?? baseURL.absoluteString) \(operationID) \(request.method) \(request.path ?? "")"
    func logRequest(attempt: Int, maxAttemptCount: Int) {
      Self.logger.debug("Sending request \(requestContext, privacy: .public) attempt \(attempt, privacy: .public)/\(maxAttemptCount, privacy: .public)")
    }

    guard case .upToAttempts(count: let maxAttemptCount) = policy else {
      Self.logger.debug("Sending request \(requestContext, privacy: .public)")
      return try await next(request, body, baseURL)
    }
    if let body {
      guard body.iterationBehavior == .multiple else {
        Self.logger.debug("Sending request \(requestContext, privacy: .public)")
        return try await next(request, body, baseURL)
      }
    }

    func willRetry(attempt: Int, response: HTTPResponse?) async throws {
      switch delay {
      case .none:
        return
      case .constant(let seconds):
        try await Task.sleep(for: .seconds(seconds))
      case .exponentialWithJitter(let base, let maxSeconds):
        if let retryAfter = response?.retryAfterSeconds {
          try await Task.sleep(for: .seconds(min(retryAfter, maxSeconds)))
          return
        }
        let cappedExponential = min(base * pow(2, Double(attempt - 1)), maxSeconds)
        try await Task.sleep(for: .seconds(Double.random(in: 0...cappedExponential)))
      }
    }
    let retryContext = "\(baseURL.host() ?? baseURL.absoluteString) \(operationID)"

    for attempt in 1...maxAttemptCount {
      let (response, responseBody): (HTTPResponse, HTTPBody?)
      if signals.contains(.errorThrown) {
        do {
          logRequest(attempt: attempt, maxAttemptCount: maxAttemptCount)
          (response, responseBody) = try await next(request, body, baseURL)
        } catch {
          if error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw error
          }

          if attempt == maxAttemptCount {
            throw error
          } else {
            Self.logger.error("Retrying \(retryContext, privacy: .public) after error on attempt \(attempt, privacy: .public)/\(maxAttemptCount, privacy: .public)")
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
            try await willRetry(attempt: attempt, response: nil)
            continue
          }
        }
      } else {
        logRequest(attempt: attempt, maxAttemptCount: maxAttemptCount)
        (response, responseBody) = try await next(request, body, baseURL)
      }
      if signals.contains(response.status.code) && attempt < maxAttemptCount {
        Self.logger.debug(
          "Retrying \(retryContext, privacy: .public) with code \(response.status.code, privacy: .public) on attempt \(attempt, privacy: .public)/\(maxAttemptCount, privacy: .public)"
        )
        try await willRetry(attempt: attempt, response: response)
        continue
      } else {
        return (response, responseBody)
      }
    }
    preconditionFailure("Unreachable")
  }
}

private extension HTTPResponse {
  var retryAfterSeconds: TimeInterval? {
    guard let name = HTTPField.Name("Retry-After"),
      let value = headerFields[name],
      let seconds = TimeInterval(value)
    else { return nil }
    return seconds
  }
}

extension Set where Element == RetryingMiddleware.RetryableSignal {
  func contains(_ code: Int) -> Bool {
    for signal in self {
      switch signal {
      case .code(let int): if code == int { return true }
      case .range(let range): if range.contains(code) { return true }
      case .errorThrown: break
      }
    }
    return false
  }
}
