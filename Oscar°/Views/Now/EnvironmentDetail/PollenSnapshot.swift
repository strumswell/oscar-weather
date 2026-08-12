import SwiftUI

struct PollenSnapshot: Identifiable {
    let id: String
    let label: String
    let value: Double
    let tier: PollenTier
    let tierLabel: String
    let color: Color
}
