//
//  OscarWidgetsBundle.swift
//  OscarWidgetsBundle
//
//  Created by Philipp Bolte on 25.10.20.
//

import WidgetKit
import SwiftUI

@main
struct OscarWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        #if os(iOS)
        NowTodayWidget()
        RadarWidget()
        DailyForecastWidget()
        PlacesWidget()
        StationsListWidget()
        AirWidget()
        SunWidget()
        ClimateWidget()
        RainRadarLiveActivityWidget()
        RadarControl()
        WeatherControl()
        #endif
        RainTimelineLockScreenWidget()
        StationWidget()
        TemperatureLockScreenWidget()
        HourlyLockScreenWidget()
        PrecipitationLockScreenWidget()
        UVIndexLockScreenWidget()
        WindLockScreenWidget()
    }
}
