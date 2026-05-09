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
        RadarWidget()
        NowTodayWidget()
        GlobalRadarWidget()
        #endif
        TemperatureLockScreenWidget()
        PrecipitationLockScreenWidget()
    }
}
