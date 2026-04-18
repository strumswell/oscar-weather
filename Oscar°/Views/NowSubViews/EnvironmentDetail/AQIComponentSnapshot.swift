import SwiftUI

struct AQIComponentSnapshot: Identifiable {
    let id: String
    let label: String
    let value: Double
    let accentColor: Color
    let status: String
    let statusColor: Color
    let explanationBodyKey: String
}
