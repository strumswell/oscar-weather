//
//  Color-Interpolation.swift
//  Weather
//
//  Created by Paul Hudson on 16/11/2021.
//

import SwiftUI

extension Color {
    func getComponents() -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        let uiColor = UIColor(self)
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }

    func interpolated(to other: Color, amount: Double) -> Color {
        let componentsFrom = self.getComponents()
        let componentsTo = other.getComponents()

        let newRed = (1 - amount) * componentsFrom.red + (amount * componentsTo.red)
        let newGreen = (1 - amount) * componentsFrom.green + (amount * componentsTo.green)
        let newBlue = (1 - amount) * componentsFrom.blue + (amount * componentsTo.blue)
        let newOpacity = (1 - amount) * componentsFrom.alpha + (amount * componentsTo.alpha)

        return Color(.displayP3, red: newRed, green: newGreen, blue: newBlue, opacity: newOpacity)
    }
}
