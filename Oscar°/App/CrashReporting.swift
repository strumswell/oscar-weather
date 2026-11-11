//
//  CrashReporting.swift
//  Oscar°
//

import Foundation
import Sentry

enum CrashReporting {
    static let enabledKey = "crashReportsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? OnboardingCoordinator.hasCompleted
    }

    static var hasAnswered: Bool {
        UserDefaults.standard.object(forKey: enabledKey) != nil
    }

    static func answer(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    static func start() {
        guard !SentrySDK.isEnabled else { return }
        SentrySDK.start { options in
            options.dsn = "https://f6b7fe82cd8cd8bb11dc0dc38db42255@o4507143648772096.ingest.de.sentry.io/4507143650148432"
            options.debug = false
            options.tracesSampleRate = 0.5

            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.enableMetricKit = true
            options.enableTimeToFullDisplayTracing = true
            options.swiftAsyncStacktraces = true

            options.beforeBreadcrumb = { crumb in
                crumb.data = crumb.data?.mapValues { value -> Any in
                    guard let text = value as? String else { return value }
                    return redactingAPIKey(text)
                }
                return crumb
            }
            options.beforeSendSpan = { span in
                if let query = span.data["http.query"] as? String {
                    span.setData(value: redactingAPIKey(query), key: "http.query")
                }
                return span
            }
            options.beforeSend = { event in
                event.request?.queryString = event.request?.queryString.map(redactingAPIKey)
                event.request?.url = event.request?.url.map(redactingAPIKey)
                return event
            }
        }
    }

    private static func redactingAPIKey(_ text: String) -> String {
        guard let key = OpenMeteoCustomer.apiKey else { return text }
        return text.replacingOccurrences(of: key, with: "[redacted]")
    }

    static func stop() {
        SentrySDK.close()
    }
}
