import UIKit

enum Haptics {
    @MainActor static func impact() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
    }

    @MainActor static func purr() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)
    }

    @MainActor static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @MainActor static func land() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6)
    }

    @MainActor static func chomp() {
        let bite = UIImpactFeedbackGenerator(style: .rigid)
        bite.impactOccurred(intensity: 0.6)
        Task {
            try? await Task.sleep(for: .milliseconds(70))
            bite.impactOccurred(intensity: 0.3)
        }
    }

    @MainActor static func stamp() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
    }

    @MainActor static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
