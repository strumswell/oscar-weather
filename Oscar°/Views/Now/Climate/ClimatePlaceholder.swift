import SwiftUI

struct ClimatePlaceholder: View {
    let isThrottled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 15)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 190, height: 13)
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)).frame(height: 54)
                .overlay {
                    if isThrottled { ProgressView().tint(.secondary) }
                }
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 230, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
        .clipShape(.rect(cornerRadius: 12))
        .cardBorder(RoundedRectangle(cornerRadius: 12))
    }
}
