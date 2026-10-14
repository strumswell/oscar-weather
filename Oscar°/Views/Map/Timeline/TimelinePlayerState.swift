import SwiftUI
import Observation

// MARK: - Shared player-state surface

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
    func advanceFrame()
    func cancelInternalTimer()
}

extension OscarRadarState: TimelinePlayerState {}
extension ModelGridLayerState: TimelinePlayerState {}
extension CloudLayerState: TimelinePlayerState {}

// MARK: - Radar continued by the model

@MainActor
@Observable
final class CombinedTimelineState: TimelinePlayerState {
    let radar = OscarRadarState()
    let model = ModelGridLayerState()
    private var selectsModel = false

    var includesModel: Bool {
        SettingService.shared.radarModelContinuation
            && model.startsAfter != nil
            && model.currentLayer == radar.region.continuationLayer
    }

    var modelStartIndex: Int? {
        includesModel && !model.frameTimestamps.isEmpty ? radar.frameTimestamps.count : nil
    }

    var isShowingModel: Bool { selectsModel && modelStartIndex != nil }

    var frameTimestamps: [String] {
        includesModel ? radar.frameTimestamps + model.frameTimestamps : radar.frameTimestamps
    }

    var currentFrameIndex: Int {
        get {
            isShowingModel ? radar.frameTimestamps.count + model.currentFrameIndex : radar.currentFrameIndex
        }
        set {
            if let start = modelStartIndex, newValue >= start {
                if !selectsModel { radar.pause() }
                selectsModel = true
                model.currentFrameIndex = newValue - start
            } else {
                if selectsModel { model.pause() }
                selectsModel = false
                radar.currentFrameIndex = newValue
            }
        }
    }

    var currentFrameTimestamp: String? {
        isShowingModel ? model.currentFrameTimestamp : radar.currentFrameTimestamp
    }

    var isCurrentFrameLive: Bool { !isShowingModel && radar.isCurrentFrameLive }

    var isPlaying: Bool { radar.isPlaying || model.isPlaying }
    var isLoading: Bool { radar.isLoading }
    var error: String? { radar.error ?? (includesModel ? model.error : nil) }
    var hasAnyLoadedFrame: Bool { radar.hasAnyLoadedFrame }
    var loadedFrameIndices: Set<Int> { merged(radar.loadedFrameIndices, model.loadedFrameIndices) }
    var loadingFrameIndices: Set<Int> { merged(radar.loadingFrameIndices, model.loadingFrameIndices) }

    private func merged(_ radarIndices: Set<Int>, _ modelIndices: Set<Int>) -> Set<Int> {
        guard includesModel else { return radarIndices }
        let offset = radar.frameTimestamps.count
        return radarIndices.union(modelIndices.lazy.map { $0 + offset })
    }

    func play() { isShowingModel ? model.play() : radar.play() }

    func advanceFrame() {
        guard modelStartIndex != nil else { return radar.advanceFrame() }
        let loaded = loadedFrameIndices
        guard let next = nextLoadedIndex(in: frameTimestamps.indices.map(loaded.contains),
                                         after: currentFrameIndex) else { return }
        let wasShowingModel = isShowingModel
        currentFrameIndex = next
        if isShowingModel != wasShowingModel { play() }
    }

    func pause() {
        radar.pause()
        model.pause()
    }

    func beginScrubbing() {
        radar.beginScrubbing()
        model.beginScrubbing()
    }

    func endScrubbing() {
        radar.endScrubbing()
        model.endScrubbing()
    }

    func cancelInternalTimer() {
        radar.cancelInternalTimer()
        model.cancelInternalTimer()
    }
}

// MARK: - Shared timeline helpers

func closestIndexToNow(_ timestamps: [String]) -> Int? {
    guard !timestamps.isEmpty else { return nil }
    return closestTimestampIndex(in: timestamps.map(parseFrameDate))
}

enum TimelineFormatters {
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
