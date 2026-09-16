import SwiftUI
import Observation

// MARK: - Shared player-state surface

/// The slice of OscarRadarState / ModelGridLayerState that the unified timeline
/// chip drives. Both are @MainActor @Observable classes; property reads through
/// the existential still register with SwiftUI's observation tracking.
@MainActor
protocol TimelinePlayerState: AnyObject, Observable {
    var frameTimestamps: [String] { get }
    var currentFrameIndex: Int { get set }
    var isPlaying: Bool { get }
    var isLoading: Bool { get }
    var error: String? { get }
    var loadedFrameIndices: Set<Int> { get }
    var loadingFrameIndices: Set<Int> { get }
    var hasAnyLoadedFrame: Bool { get }
    func play()
    func pause()
    func beginScrubbing()
    func endScrubbing()
}

extension OscarRadarState: TimelinePlayerState {}
extension ModelGridLayerState: TimelinePlayerState {}
extension CloudLayerState: TimelinePlayerState {}

// MARK: - Shared timeline helpers

/// Index of the frame closest to the wall clock (the scrubber's "now" marker).
func closestIndexToNow(_ timestamps: [String]) -> Int? {
    guard !timestamps.isEmpty else { return nil }
    return closestTimestampIndex(in: timestamps.map(parseFrameDate))
}

enum TimelineFormatters {
    /// Compact signed offsets for the status pill / axis end ("+35 Min.", "+2 Std.").
    static let delta: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        return f
    }()
    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
}
