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
    nonisolated(unsafe) static let delta: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        return f
    }()
    nonisolated(unsafe) static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()
}

// MARK: - Layer-specific wrappers

struct OscarRadarTimelineControls: View {
    let radarState: OscarRadarState
    /// Tapping the source badge (e.g. "DWD Radar") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: radarState,
            sourceLabel: sourceLabel,
            shortSourceLabel: shortSourceLabel,
            isLive: radarState.isCurrentFrameLive,
            loadingLabel: "Oscar Radar-Daten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }

    private var sourceLabel: String {
        switch radarState.region {
        case .germany: "DWD Radar"
        case .europe: "EUMETNET Radar"
        case .usa: "NOAA Radar"
        case .taiwan: "CWA Radar"
        case .brasil: "REDEMET Radar"
        case .canarias: "AEMET Radar"
        }
    }

    private var shortSourceLabel: String {
        switch radarState.region {
        case .germany: "DWD"
        case .europe: "EUMETNET"
        case .usa: "NOAA"
        case .taiwan: "CWA"
        case .brasil: "REDEMET"
        case .canarias: "AEMET"
        }
    }
}

struct CloudTimelineControls: View {
    let cloudState: CloudLayerState
    /// Tapping the source badge opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: cloudState,
            sourceLabel: "Meteosat",
            shortSourceLabel: "Meteosat",
            isLive: cloudState.isCurrentFrameLive,
            loadingLabel: "Satellitenbilder werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }
}

struct WeatherTileTimelineControls: View {
    let imageState: ModelGridLayerState
    /// Tapping the source badge (e.g. "DWD ICON-D2") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: imageState,
            sourceLabel: imageState.currentLayer?.sourceLabel ?? "",
            shortSourceLabel: shortSourceLabel,
            isLive: false,
            loadingLabel: "Wetterdaten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }

    private var shortSourceLabel: String {
        switch imageState.currentLayer {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: "ICON-D2"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: "ECMWF"
        case nil: ""
        }
    }
}
