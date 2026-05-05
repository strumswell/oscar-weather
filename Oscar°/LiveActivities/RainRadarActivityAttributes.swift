//
//  RainRadarActivityAttributes.swift
//  Oscar°
//

import ActivityKit
import Foundation

struct RainRadarActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case upcoming
            case raining
            case endingSoon
            case ended
            case stale
        }

        struct TimelineBucket: Codable, Hashable, Identifiable {
            var id: String { timestamp }

            let timestamp: String
            let precipitation: Double
            let isWet: Bool
        }

        let phase: Phase
        let locationName: String
        let startsAt: String?
        let endsAt: String?
        let lastObservedAt: String
        let staleAt: String
        let intensityLabel: String
        let maxIntensity: Double
        let minutesUntilStart: Int?
        let minutesUntilEnd: Int?
        let timeline: [TimelineBucket]
        let isEndOpenEnded: Bool
    }

    let locationName: String
    let subscriptionId: String
}
