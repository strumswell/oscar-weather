//
//  OscarRadarState.swift
//  Oscar°
//
//  Timeline state for the live radar layer: metadata + frame grid loading,
//  playback and scrubbing.
//

import Foundation
import Observation
import UIKit
import os

/// Inputs of the snow overlay (see `RadarCustomStyleLayer.setSnow`): hourly sea-level
/// wet-bulb rasters plus one terrain raster, both over the radar's image bounds.
struct RadarSnowOverlay {
    struct Step {
        let key: String
        let date: Date
        let payload: RadarGridPayload
    }
    let id: String
    /// The terrain only changes with the region, so the layer keeps its texture across hours.
    let terrainID: String
    let steps: [Step]
    /// Kept deflated (under 1 MB); the layer inflates it once into its texture.
    let terrainData: Data
    let snowBelow: Double
    let rainAbove: Double
    let lapsePerMeter: Double
    let fieldScale: Double
    let fieldOffset: Double
    let terrainScale: Double
}

@MainActor
@Observable
final class OscarRadarState {
    var frames: [OscarRadarFrame?] = []
    private(set) var snow: RadarSnowOverlay?
    /// Set by the map from the user's setting; the assets load only while it is on.
    @ObservationIgnored var snowWanted = false {
        didSet { if snowWanted != oldValue { refreshSnow() } }
    }
    /// Whether the last frames response carried snow data; drives the toggle's visibility.
    private(set) var snowAvailable = false
    @ObservationIgnored private var snowInfo: Components.Schemas.RadarSnow? {
        didSet { if snowAvailable != (snowInfo != nil) { snowAvailable = snowInfo != nil } }
    }
    @ObservationIgnored private var snowTask: Task<Void, Never>?
    @ObservationIgnored private var snowTerrainTask: Task<Void, Never>?
    /// Hourly fields + coarse relief load while the toggle is on; the terrain only once snow is possible in view.
    @ObservationIgnored private var snowStepsID: String?
    @ObservationIgnored private var snowLoadingID: String?
    @ObservationIgnored private var snowSteps: [RadarSnowOverlay.Step] = []
    @ObservationIgnored private var snowRelief: RadarGridPayload?
    @ObservationIgnored private var snowActive = false
    @ObservationIgnored private var snowView: OscarRadarBounds?
    @ObservationIgnored private var snowEvaluatedFor: (String, OscarRadarBounds?, OscarRadarBounds?) = ("", nil, nil)

    private(set) var frameTimestamps: [String] = []

    var bounds: OscarRadarBounds?
    private(set) var motion: RadarMotionData?
    private(set) var region: RadarRegion = .germany
    var isLoading: Bool = false
    var currentFrameIndex: Int = 0 {
        didSet {
            guard currentFrameIndex != oldValue else { return }
            handleFrameSelectionChanged()
        }
    }
    var isPlaying: Bool = false
    var error: String?
    private(set) var loadingFrameIndices: Set<Int> = []
    private(set) var loadedFrameIndices: Set<Int> = []
    private(set) var renderFrameIndex: Int?
    private(set) var isMapInteracting = false
    @ObservationIgnored var preloadsWide = true

    @ObservationIgnored private let playback = PlaybackTicker()
    @ObservationIgnored private var frameInfos: [RadarFrameInfo] = []
    @ObservationIgnored private var frameDates: [Date?] = []
    @ObservationIgnored private var loadSessionID = UUID()
    @ObservationIgnored private var suppressSelectionSideEffects = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var loadTasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var failedFrameIndices: Set<Int> = []
    @ObservationIgnored private var loadsHeld = false
    @ObservationIgnored private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var lastMetadataLoad: Date?
    private static let metadataStaleAfter: TimeInterval = 10 * 60
    private static let instances = NSHashTable<OscarRadarState>.weakObjects()

    init() {
        Self.instances.add(self)
    }

    // MARK: - Derived state

    var currentFrame: OscarRadarFrame? {
        frame(at: renderFrameIndex ?? currentFrameIndex)
    }

    var nextFrame: OscarRadarFrame? {
        guard let anchor = renderFrameIndex ?? (isSelectedFrameReady ? currentFrameIndex : nil) else { return nil }
        let loaded = frames.map { $0 != nil }
        guard let nextIndex = nextLoadedIndex(in: loaded, after: anchor) else { return nil }
        return frame(at: nextIndex)
    }

    var currentFrameTimestamp: String? {
        guard currentFrameIndex < frameTimestamps.count else { return nil }
        return frameTimestamps[currentFrameIndex]
    }

    var isCurrentFrameLive: Bool {
        guard !frameDates.isEmpty else { return false }
        return currentFrameIndex == closestTimestampIndex(in: frameDates)
    }

    var hasAnyLoadedFrame: Bool {
        frames.contains { $0 != nil }
    }

    var isSelectedFrameReady: Bool {
        frames.indices.contains(currentFrameIndex) && frames[currentFrameIndex] != nil
    }

    // MARK: - Grid residency

    private static let gridResidencyBudget = adaptiveCacheBudget(
        fraction: 0.16, floor: 64 * 1024 * 1024, cap: 512 * 1024 * 1024)

    private func residentFrameIndices(around center: Int) -> Set<Int> {
        let bytesPerFrame = frames.lazy.compactMap { $0 }
            .map { $0.gridPayload.width * $0.gridPayload.height }
            .max() ?? 4_000_000
        var resident = residencyWindow(count: frames.count, center: center,
                                       bytesPerFrame: bytesPerFrame, budget: Self.gridResidencyBudget)
        if !frameDates.isEmpty {
            resident.insert(closestTimestampIndex(in: frameDates))
        }
        if let renderFrameIndex {
            resident.insert(renderFrameIndex)
        }
        return resident
    }

    private func evictFrames(outside resident: Set<Int>) {
        for index in frames.indices where frames[index] != nil && !resident.contains(index) {
            frames[index] = nil
            loadedFrameIndices.remove(index)
        }
    }

    static func purgeDecodedGrids() {
        for state in instances.allObjects {
            state.loadsHeld = true
            let anchor = state.renderFrameIndex ?? state.currentFrameIndex
            var keep: Set<Int> = [anchor]
            if let next = nextLoadedIndex(in: state.frames.map { $0 != nil }, after: anchor) {
                keep.insert(next)
            }
            state.evictFrames(outside: keep)
        }
    }

    // MARK: - Region

    func setRegion(_ newRegion: RadarRegion) {
        guard newRegion != region else { return }
        region = newRegion
        resetForSourceChange()
    }

    private func resetForSourceChange() {
        snowInfo = nil
        clearSnow()
        bootstrapTask?.cancel()
        cancelFrameLoads()
        pause()

        loadSessionID = UUID()
        lastMetadataLoad = nil
        suppressSelectionSideEffects = true
        frames = []
        frameInfos = []
        frameTimestamps = []
        frameDates = []
        bounds = nil
        motion = nil
        loadedFrameIndices.removeAll()
        renderFrameIndex = nil
        currentFrameIndex = 0
        suppressSelectionSideEffects = false
    }

    func reloadForCurrentRegion() async {
        await loadAllFrames()
    }

    func refreshIfStale() async {
        guard !isLoading else { return }
        if hasAnyLoadedFrame, let lastMetadataLoad,
           Date().timeIntervalSince(lastMetadataLoad) < Self.metadataStaleAfter {
            return
        }
        await reloadForCurrentRegion()
    }

    // MARK: - Staged frames

    func showStagedFrames(_ staged: [OscarRadarFrame], dates: [Date], bounds: OscarRadarBounds, motion: RadarMotionData?) {
        resetForSourceChange()
        suppressSelectionSideEffects = true
        self.bounds = bounds
        self.motion = motion
        frameTimestamps = staged.map(\.timestamp)
        frameDates = dates
        frames = staged
        loadedFrameIndices = Set(staged.indices)
        currentFrameIndex = closestTimestampIndex(in: dates)
        suppressSelectionSideEffects = false
        lastMetadataLoad = Date()
    }

    // MARK: - Loading

    func loadAllFrames() async {
        await loadFrames()
    }

    func waitForFrames() async {
        await bootstrapTask?.value
        while !loadingFrameIndices.isEmpty { await nextLoadCompletion() }
    }

    // MARK: - Playback

    func play() {
        guard hasAnyLoadedFrame else { return }
        isPlaying = true
        loadsHeld = false
        pumpLoads()
        playback.start(interval: .milliseconds(500)) { [weak self] in self?.advanceFrame() }
    }

    func pause() {
        isPlaying = false
        playback.stop()
    }

    func cancelInternalTimer() {
        playback.stop()
    }

    func advanceFrame() {
        guard isPlaying, !frames.isEmpty else { return }
        let loaded = frames.map { $0 != nil }
        guard let next = nextLoadedIndex(in: loaded, after: currentFrameIndex) else {
            return
        }
        currentFrameIndex = next
    }

    func beginScrubbing() {
        pause()
    }

    func endScrubbing() {}

    func beginMapInteraction() {
        guard !isMapInteracting else { return }
        isMapInteracting = true
    }

    func endMapInteraction() {
        guard isMapInteracting else { return }
        isMapInteracting = false
        pumpLoads()
    }

    // MARK: - Private Helpers

    private func loadFrames() async {
        bootstrapTask?.cancel()
        cancelFrameLoads()

        let sessionID = UUID()
        loadSessionID = sessionID
        isLoading = true
        error = nil
        renderFrameIndex = nil

        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            do {
                let (allFrameInfos, boundsInfo, snowInfo) = try await Self.fetchFrameInfos(region: self.region)
                guard !Task.isCancelled, self.loadSessionID == sessionID else { return }
                self.snowInfo = snowInfo
                self.refreshSnow()
                let pastCutoff = Date().addingTimeInterval(-25 * 60)
                let fetchedFrameInfos = allFrameInfos.filter { info in
                    guard let date = parseFrameDate(info.timestamp) else { return true }
                    return date >= pastCutoff
                }
                guard !fetchedFrameInfos.isEmpty else {
                    self.isLoading = false
                    return
                }

                let timestamps = fetchedFrameInfos.map(\.timestamp)
                let dates = timestamps.map(parseFrameDate)
                let closest = closestTimestampIndex(in: dates)

                self.suppressSelectionSideEffects = true
                self.bounds = boundsInfo.asDomain
                self.frameInfos = fetchedFrameInfos
                self.frameTimestamps = timestamps
                self.frameDates = dates
                self.frames = Array(repeating: nil, count: fetchedFrameInfos.count)
                self.loadedFrameIndices = []
                self.currentFrameIndex = closest
                self.suppressSelectionSideEffects = false
                self.lastMetadataLoad = Date()

                let motionRegion = self.region
                Task { [weak self] in
                    let data = await Self.fetchMotionData(region: motionRegion)
                    guard let self, self.loadSessionID == sessionID else { return }
                    self.motion = data
                }

                self.loadsHeld = false
                self.pumpLoads()
                while !self.hasAnyLoadedFrame, !self.loadingFrameIndices.isEmpty, self.loadSessionID == sessionID {
                    await self.nextLoadCompletion()
                }
                guard self.loadSessionID == sessionID else { return }
                self.isLoading = false
            } catch {
                guard self.loadSessionID == sessionID else { return }
                self.error = String(localized: "Fehler beim Laden: \(error.localizedDescription)")
                self.isLoading = false
            }
        }

        await bootstrapTask?.value
    }

    private func handleFrameSelectionChanged() {
        guard !suppressSelectionSideEffects else { return }
        guard !frameInfos.isEmpty, frameInfos.indices.contains(currentFrameIndex) else { return }

        evictFrames(outside: residentFrameIndices(around: currentFrameIndex))
        showNearestLoadedFrame()
        if !isPlaying { failedFrameIndices.removeAll() }
        loadsHeld = false
        pumpLoads()
    }

    private func showNearestLoadedFrame() {
        guard let nearest = nearestLoadedIndex(in: frames.map { $0 != nil }, around: currentFrameIndex),
              nearest != renderFrameIndex else { return }
        if let renderFrameIndex, abs(renderFrameIndex - currentFrameIndex) <= abs(nearest - currentFrameIndex) { return }
        renderFrameIndex = nearest
    }

    private func pumpLoads() {
        guard !loadsHeld, !frameInfos.isEmpty else { return }
        let wide = preloadsWide && allowsBackgroundPreload() && !isMapInteracting
        let focus = Set(prioritizedFrameIndices(count: frames.count, around: currentFrameIndex).prefix(5))
        let resident = residentFrameIndices(around: currentFrameIndex)
        let picks = loadsToStart(count: frames.count, center: currentFrameIndex,
                                 inFlight: loadingFrameIndices.count, limit: frameLoadLimit()) { index in
            frames[index] == nil && !loadingFrameIndices.contains(index) && !failedFrameIndices.contains(index)
                && resident.contains(index) && (wide || focus.contains(index))
        }
        for index in picks { startLoad(at: index) }
    }

    private func startLoad(at index: Int) {
        let sessionID = loadSessionID
        let info = frameInfos[index]
        let region = self.region
        loadingFrameIndices.insert(index)
        loadTasks[index] = Task { [weak self] in
            let grid = await Self.loadGridIndices(for: info, region: region)
            self?.finishLoad(at: index, info: info, grid: grid, sessionID: sessionID)
        }
    }

    private func finishLoad(at index: Int, info: RadarFrameInfo, grid: RadarGridPayload?, sessionID: UUID) {
        guard loadSessionID == sessionID else { return }
        loadingFrameIndices.remove(index)
        loadTasks[index] = nil

        if let grid {
            if frameInfos.indices.contains(index), frameInfos[index].key == info.key, frames.indices.contains(index),
               residentFrameIndices(around: currentFrameIndex).contains(index) {
                frames[index] = OscarRadarFrame(key: info.key, timestamp: info.timestamp,
                                                gridIndices: grid.indices, width: grid.width, height: grid.height)
                loadedFrameIndices.insert(index)
                showNearestLoadedFrame()
            }
        } else {
            failedFrameIndices.insert(index)
        }

        pumpLoads()
        if isLoading, hasAnyLoadedFrame || loadingFrameIndices.isEmpty {
            isLoading = false
        }
        resumeLoadWaiters()
    }

    private func cancelFrameLoads() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
        loadingFrameIndices.removeAll()
        failedFrameIndices.removeAll()
        loadsHeld = false
        resumeLoadWaiters()
    }

    private func nextLoadCompletion() async {
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    private func resumeLoadWaiters() {
        let waiters = loadWaiters
        loadWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func frame(at index: Int?) -> OscarRadarFrame? {
        guard let index, frames.indices.contains(index) else { return nil }
        return frames[index]
    }

    private static func fetchFrameInfos(region: RadarRegion) async throws
        -> ([RadarFrameInfo], Components.Schemas.RadarBounds, Components.Schemas.RadarSnow?) {
        let response = try await APIClient.shared.radarFrames(region: region.pathComponent)
        return (response.frames, response.image_bounds ?? response.bounds, response.snow)
    }

    private func clearSnow() {
        snowTask?.cancel()
        snowTerrainTask?.cancel()
        snowTerrainTask = nil
        snowStepsID = nil
        snowLoadingID = nil
        snowSteps = []
        snowRelief = nil
        snowActive = false
        snowEvaluatedFor = ("", nil, nil)
        if snow != nil { snow = nil }
    }

    private func refreshSnow() {
        guard snowWanted, let info = snowInfo, !info.steps.isEmpty else {
            clearSnow()
            return
        }
        let region = self.region.pathComponent
        let id = "\(region)|" + info.steps.map(\.key).joined(separator: ",")
        guard snowStepsID != id else {
            // Retries a failed terrain download on the next metadata reload.
            if snowActive, snow == nil, snowTerrainTask == nil {
                snowEvaluatedFor = ("", nil, nil)
                evaluateSnow()
            }
            return
        }
        guard snowLoadingID != id else { return }
        snowTask?.cancel()
        snowLoadingID = id
        // A new hour only adds a step: keep the steps already decoded.
        let previous = snowSteps
        let relief = snowRelief
        snowTask = Task { [weak self] in
            var fetchedRelief = relief
            if fetchedRelief == nil, let data = try? await APIClient.shared.radarSnowRelief(region: region) {
                fetchedRelief = await RadarFrameDecodeLane.shared.decodeRawGrid(data)
            }
            var steps: [RadarSnowOverlay.Step] = []
            for step in info.steps {
                if let known = previous.first(where: { $0.key == step.key }) {
                    steps.append(known)
                    continue
                }
                guard let date = parseFrameDate(step.timestamp),
                      let data = try? await APIClient.shared.radarSnowField(region: region, key: step.key),
                      let payload = await RadarFrameDecodeLane.shared.decodeRawGrid(data) else { continue }
                steps.append(.init(key: step.key, date: date, payload: payload))
            }
            guard let self, !Task.isCancelled else { return }
            // Whoever cancelled this task already reset or replaced snowLoadingID.
            if self.snowLoadingID == id { self.snowLoadingID = nil }
            guard !steps.isEmpty, self.snowWanted, self.region.pathComponent == region else { return }
            self.snowStepsID = id
            self.snowSteps = steps
            self.snowRelief = fetchedRelief
            self.evaluateSnow()
        }
    }

    /// Called from the map's sync while it is not being moved.
    func setSnowView(_ view: OscarRadarBounds?) {
        snowView = view
        evaluateSnow()
    }

    private func evaluateSnow() {
        guard snowWanted, let info = snowInfo, let stepsID = snowStepsID else { return }
        let key = (stepsID, snowView, bounds)
        guard key != snowEvaluatedFor else { return }
        snowEvaluatedFor = key
        if let relief = snowRelief {
            snowActive = Self.snowPossible(
                fields: snowSteps.map(\.payload), relief: relief, view: snowView, radar: bounds,
                fieldScale: info.field_scale, fieldOffset: info.field_offset,
                lapse: info.lapse_per_m * info.terrain_scale,
                threshold: info.rain_above + (snowActive ? 2.0 : 1.0))
        } else {
            snowActive = true
        }
        guard snowActive else {
            snowTerrainTask?.cancel()
            snowTerrainTask = nil
            if snow != nil { snow = nil }
            return
        }
        let region = self.region.pathComponent
        if let current = snow, current.terrainID == region {
            if current.id != stepsID { snow = makeSnowOverlay(info: info, terrain: current.terrainData) }
            return
        }
        guard snowTerrainTask == nil else { return }
        snowTerrainTask = Task { [weak self] in
            let terrain = try? await APIClient.shared.radarSnowTerrain(region: region)
            guard let self, !Task.isCancelled else { return }
            self.snowTerrainTask = nil
            guard let terrain, self.snowActive, self.snowWanted, self.region.pathComponent == region,
                  let info = self.snowInfo else { return }
            self.snow = self.makeSnowOverlay(info: info, terrain: terrain)
        }
    }

    private func makeSnowOverlay(info: Components.Schemas.RadarSnow, terrain: Data) -> RadarSnowOverlay? {
        guard let stepsID = snowStepsID, !snowSteps.isEmpty else { return nil }
        return RadarSnowOverlay(
            id: stepsID, terrainID: region.pathComponent, steps: snowSteps, terrainData: terrain,
            snowBelow: info.snow_below, rainAbove: info.rain_above, lapsePerMeter: info.lapse_per_m,
            fieldScale: info.field_scale, fieldOffset: info.field_offset, terrainScale: info.terrain_scale)
    }

    /// True when any field cell inside `view` has a ground wet-bulb at or below `threshold` in any step.
    /// Rasters are Web-Mercator over `radar`, row 0 north. Mismatched rasters count as possible.
    nonisolated static func snowPossible(
        fields: [RadarGridPayload], relief: RadarGridPayload, view: OscarRadarBounds?, radar: OscarRadarBounds?,
        fieldScale: Double, fieldOffset: Double, lapse: Double, threshold: Double
    ) -> Bool {
        let w = relief.width, h = relief.height
        guard !fields.contains(where: { $0.width != w || $0.height != h }) else { return true }
        var cols = 0...(w - 1), rows = 0...(h - 1)
        if let view, let radar, radar.east > radar.west, radar.north > radar.south {
            let west = max(view.west, radar.west), east = min(view.east, radar.east)
            let north = min(view.north, radar.north), south = max(view.south, radar.south)
            guard west <= east, south <= north else { return false }
            let top = WebMercator.unitY(latitude: radar.north)
            let spanY = WebMercator.unitY(latitude: radar.south) - top
            func col(_ lon: Double) -> Int { min(w - 1, max(0, Int(((lon - radar.west) / (radar.east - radar.west) * Double(w)).rounded(.down)))) }
            func row(_ lat: Double) -> Int { min(h - 1, max(0, Int(((WebMercator.unitY(latitude: lat) - top) / spanY * Double(h)).rounded(.down)))) }
            cols = col(west)...col(east)
            rows = row(north)...row(south)
        }
        return relief.indices.withUnsafeBufferPointer { ground in
            for field in fields {
                let hit = field.indices.withUnsafeBufferPointer { values in
                    for y in rows {
                        for x in cols {
                            let i = y * w + x
                            if Double(values[i]) * fieldScale + fieldOffset - lapse * Double(ground[i]) <= threshold { return true }
                        }
                    }
                    return false
                }
                if hit { return true }
            }
            return false
        }
    }

    private static func loadGridIndices(for frameInfo: RadarFrameInfo, region: RadarRegion) async -> RadarGridPayload? {
        let fetched: Data?
        do {
            fetched = try await APIClient.shared.radarGrid(
                region: region.pathComponent,
                key: frameInfo.key)
        } catch {
            return nil
        }
        guard let data = fetched else {
            return RadarGridPayload(indices: [0], width: 1, height: 1)
        }
        return await RadarFrameDecodeLane.shared.decodeRawGrid(data)
    }

    nonisolated static func minutesBetween(_ from: String, _ to: String) -> Int? {
        guard let a = parseFrameDate(from), let b = parseFrameDate(to) else { return nil }
        return Int((b.timeIntervalSince(a) / 60).rounded())
    }

    private static func fetchMotionData(region: RadarRegion) async -> RadarMotionData? {
        guard let payload = try? await APIClient.shared.radarMotion(region: region.pathComponent) else { return nil }
        return RadarMotionData(payload: payload)
    }

    deinit {
        bootstrapTask?.cancel()
        loadTasks.values.forEach { $0.cancel() }
    }
}
