import UIKit

enum Haptics {
    @MainActor static func impact() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }

    @MainActor static func purr() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
    }
}
