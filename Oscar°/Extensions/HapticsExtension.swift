//
//  HapticsExtension.swift
//  Oscar°
//
//  Created by Philipp Bolte on 23.04.24.
//

import Foundation
import SwiftUI

extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func playHapticFeedback() {
        let hapticFeedback = UIImpactFeedbackGenerator(style: .rigid)
        hapticFeedback.impactOccurred(intensity: 0.5)
    }
}
