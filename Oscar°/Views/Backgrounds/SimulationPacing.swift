//
//  SimulationPacing.swift
//  Oscar°
//
//  Frame pacing for the animated weather layers. Shared by the iOS simulation
//  and the watch app, which runs everything at the reduced background rate.
//

import Foundation

enum SimulationPacing: Equatable {
    case active
    case background
    case still

    static let backgroundFPS: Double = 8

    func minimumInterval(base: Double?) -> Double? {
        self == .background ? 1.0 / Self.backgroundFPS : base
    }

    var isPaused: Bool { self == .still }
}
