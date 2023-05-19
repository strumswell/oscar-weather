//
//  Cloud.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

class Cloud {
    enum Thickness: CaseIterable {
        case none, thin, light, regular, thick, ultra
    }

    var position: CGPoint
    let imageNumber: Int
    let speed = Double.random(in: 4...12)
    let scale: Double

    init(imageNumber: Int, scale: Double) {
        self.imageNumber = imageNumber
        self.scale = scale

        let startX = Double.random(in: -400...400)
        let startY = Double.random(in: -50...200)
        position = CGPoint(x: startX, y: startY)
    }
}
