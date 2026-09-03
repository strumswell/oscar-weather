import UIKit

enum Haptics {
    @MainActor static func impact() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }
}
