import SwiftUI

struct OscarRadarTimelineControls: View {
    let timeline: CombinedTimelineState
    var onBadgeTap: (() -> Void)?

    var body: some View {
        let model = timeline.isShowingModel ? timeline.model.currentLayer : nil
        TimelineControlsChip(
            state: timeline,
            sourceLabel: model?.sourceLabel ?? timeline.radar.region.sourceLabel,
            shortSourceLabel: model?.shortSourceLabel ?? timeline.radar.region.shortSourceLabel,
            isLive: timeline.isCurrentFrameLive,
            isForecast: false,
            forecastStartIndex: timeline.modelStartIndex,
            loadingLabel: "Oscar Radar-Daten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }
}

struct CloudTimelineControls: View {
    let cloudState: CloudLayerState
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: cloudState,
            sourceLabel: "Meteosat",
            shortSourceLabel: "Meteosat",
            isLive: cloudState.isCurrentFrameLive,
            isForecast: false,
            loadingLabel: "Satellitenbilder werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }
}

struct WeatherTileTimelineControls: View {
    let imageState: ModelGridLayerState
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: imageState,
            sourceLabel: imageState.currentLayer?.sourceLabel ?? "",
            shortSourceLabel: imageState.currentLayer?.shortSourceLabel ?? "",
            isLive: false,
            isForecast: true,
            loadingLabel: "Wetterdaten werden geladen…",
            onBadgeTap: onBadgeTap
        )
    }
}
