import SwiftUI

struct HourlyDetailInfoCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        EnvironmentDetailCard {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
