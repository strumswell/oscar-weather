//
//  MapLegendStack.swift
//  Oscar°
//

import SwiftUI

struct MapLegendStack: View {
    let settingsService: SettingService
    let timeline: CombinedTimelineState
    let cloudLayerState: CloudLayerState
    let modelGridState: ModelGridLayerState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settingsService.oscarRadarLayer {
                if timeline.hasAnyLoadedFrame,
                   let timestamp = timeline.currentFrameTimestamp {
                    RadarTimestampBadge(
                        timestamp: timestamp,
                        isLive: timeline.isCurrentFrameLive
                    )
                    ColormapVerticalLegend(colormap: .radar)
                }
                if settingsService.showStormCells {
                    StormCellLegend()
                }
            } else if settingsService.cloudLayerActive,
                      cloudLayerState.hasAnyLoadedFrame {
                if cloudLayerState.frameTimestamps.indices.contains(cloudLayerState.currentFrameIndex) {
                    RadarTimestampBadge(
                        timestamp: cloudLayerState.frameTimestamps[cloudLayerState.currentFrameIndex],
                        isLive: cloudLayerState.isCurrentFrameLive
                    )
                }
            } else if settingsService.activeTileLayer != nil,
                      modelGridState.hasAnyLoadedFrame {
                if let timestamp = modelGridState.currentFrameTimestamp {
                    RadarTimestampBadge(timestamp: timestamp, isLive: false)
                }
                if let colormap = settingsService.activeTileLayer?.colormap {
                    ColormapVerticalLegend(colormap: colormap)
                }
            }
        }
    }
}
