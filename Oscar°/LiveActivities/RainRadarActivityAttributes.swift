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
            case ending
            case ended
        }

        struct Bucket: Codable, Hashable, Identifiable {
            var id: Int { t }
            let t: Int
            let v: Double

            var date: Date { Date(timeIntervalSince1970: TimeInterval(t)) }
        }

        let phase: Phase
        let startsAt: Int?
        let endsAt: Int?
        let endIsOpen: Bool
        let nextStartsAt: Int?
        let peakMmPerHour: Double
        let observedAt: Int
        let timeline: [Bucket]
        let dismissAt: Int?
    }

    let locationName: String
    let subscriptionId: String
}

extension RainRadarActivityAttributes.ContentState {
    var startDate: Date? { startsAt.map(Self.date) }
    var endDate: Date? { endsAt.map(Self.date) }
    var nextStartDate: Date? { nextStartsAt.map(Self.date) }
    var observedDate: Date { Self.date(observedAt) }
    var dismissDate: Date? { dismissAt.map(Self.date) }

    private static func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func sample(phase: Phase, now: Date = Date()) -> Self {
        let base = Int(now.timeIntervalSince1970 / 300) * 300
        func at(_ step: Int) -> Int { base + step * 300 }
        let values: [Double]
        switch phase {
        case .upcoming:
            values = [0, 0, 0, 0, 0, 0.3, 1.2, 2.4, 3.1, 2.8, 1.6, 0.9, 0.4, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .raining:
            values = [1.8, 2.6, 3.4, 3.9, 3.2, 2.7, 2.1, 1.6, 1.1, 0.7, 0.4, 0.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .ending:
            values = [2.1, 1.4, 0.9, 0.5, 0.3, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .ended:
            values = [0.4, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1.1, 1.9, 1.2, 0, 0]
        }
        let timeline = values.enumerated().map { Bucket(t: at($0.offset - 3), v: $0.element) }
        switch phase {
        case .upcoming:
            return .init(
                phase: .upcoming, startsAt: at(2), endsAt: at(9), endIsOpen: false, nextStartsAt: nil,
                peakMmPerHour: 3.1, observedAt: at(0), timeline: timeline, dismissAt: nil
            )
        case .raining:
            return .init(
                phase: .raining, startsAt: at(-7), endsAt: at(8), endIsOpen: false, nextStartsAt: nil,
                peakMmPerHour: 3.9, observedAt: at(0), timeline: timeline, dismissAt: nil
            )
        case .ending:
            return .init(
                phase: .ending, startsAt: at(-9), endsAt: at(2), endIsOpen: false, nextStartsAt: nil,
                peakMmPerHour: 2.1, observedAt: at(0), timeline: timeline, dismissAt: nil
            )
        case .ended:
            return .init(
                phase: .ended, startsAt: at(-9), endsAt: at(-2), endIsOpen: false, nextStartsAt: at(14),
                peakMmPerHour: 2.1, observedAt: at(0), timeline: timeline, dismissAt: at(3)
            )
        }
    }
}
