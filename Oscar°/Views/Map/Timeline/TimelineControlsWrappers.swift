import SwiftUI

struct OscarRadarTimelineControls: View {
    let radarState: OscarRadarState
    /// Tapping the source badge (e.g. "DWD Radar") opens the layer picker.
    var onBadgeTap: (() -> Void)?

    var body: some View {
        TimelineControlsChip(
            state: radarState,
            sourceLabel: radarState.region.sourceLabel,
            shortSourceLabel: radarState.region.shortSourceLabel,
            isLive: radarState.isCurrentFrameLive,
            loadingLabel: "Oscar Radar-Daten werden geladen…",
            onBadgeTap: onBadgeTap
        )
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
