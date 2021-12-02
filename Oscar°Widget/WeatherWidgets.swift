//
//  File.swift
//  WeatherWidgetExtension
//
//  Created by Philipp Bolte on 25.10.20.
//

import WidgetKit
import SwiftUI

@main
struct WeatherWidgets: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        RadarWidget()
    }
}
