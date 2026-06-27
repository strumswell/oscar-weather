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

/// A middleware that retries the request under certain conditions.
///
/// Only meant to be used for illustrative purposes.
nonisolated struct RetryingMiddleware {

  private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Retry")

  /// The failure signal that can lead to a retried request.
  enum RetryableSignal: Hashable {

    /// Retry if the response code matches this code.
    case code(Int)

    /// Retry if the response code falls into this range.
    case range(Range<Int>)

    /// Retry if an error is thrown by a downstream middleware or transport.
    case errorThrown
  }

  /// The policy to use when a retryable signal hints that a retry might be appropriate.
  enum RetryingPolicy: Hashable {

    /// Don't retry.
    case never

    /// Retry up to the provided number of attempts.
    case upToAttempts(count: Int)
  }

  /// The policy of delaying the retried request.
  enum DelayPolicy: Hashable {

    /// Don't delay, retry immediately.
    case none

    /// Constant delay.
    case constant(seconds: TimeInterval)

    /// Exponential backoff with full jitter, capped at `maxSeconds`. Honors a server
    /// `Retry-After` header (delta-seconds form) when present.
    case exponentialWithJitter(base: TimeInterval, maxSeconds: TimeInterval)
  }

  /// The signals that lead to the retry policy being evaluated.
  var signals: Set<RetryableSignal>

  /// The policy used to evaluate whether to perform a retry.
  var policy: RetryingPolicy

  /// The delay policy for retries.
  var delay: DelayPolicy

  /// Creates a new retrying middleware.
  /// - Parameters:
  ///   - signals: The signals that lead to the retry policy being evaluated.
  ///   - policy: The policy used to evaluate whether to perform a retry.
  ///   - delay: The delay policy for retries.
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
        // Full jitter: a random point in [0, cappedExponential] spreads retries so many
        // clients don't hammer a rate-limited endpoint in lock-step.
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
          // Don't retry if the error is a cancellation
          if error is CancellationError {
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
  /// The `Retry-After` header parsed as delta-seconds. The HTTP-date form is not handled.
  var retryAfterSeconds: TimeInterval? {
    guard let name = HTTPField.Name("Retry-After"),
      let value = headerFields[name],
      let seconds = TimeInterval(value)
    else { return nil }
    return seconds
  }
}

extension Set where Element == RetryingMiddleware.RetryableSignal {
  /// Checks whether the provided response code matches the retryable signals.
  /// - Parameter code: The provided code to check.
  /// - Returns: `true` if the code matches at least one of the signals, `false` otherwise.
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
