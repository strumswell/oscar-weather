//
//  Cloud.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

class Cloud {
    enum Thickness: CaseIterable, Hashable {
        case none, thin, light, regular, thick, ultra
    }

    var position: CGPoint
    let imageNumber: Int
    let speed: Double
    let scale: Double

    init(
        imageNumber: Int,
        scale: Double,
        xRange: ClosedRange<Double>,
        yRange: ClosedRange<Double>,
        speedRange: ClosedRange<Double>
    ) {
        self.imageNumber = imageNumber
        self.scale = scale
        self.speed = Double.random(in: speedRange)

        let startX = Double.random(in: xRange)
        let startY = Double.random(in: yRange)
        position = CGPoint(x: startX, y: startY)
    }
}
