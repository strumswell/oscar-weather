import SwiftUI

struct EnvironmentDetailSegmentedControl: View {
    @Binding var selectedSection: EnvironmentDetailSection

    var body: some View {
        Picker("Umweltdetails", selection: $selectedSection) {
            Text(EnvironmentDetailSection.aqi.title).tag(EnvironmentDetailSection.aqi)
            Text(EnvironmentDetailSection.uv.title).tag(EnvironmentDetailSection.uv)
            Text(EnvironmentDetailSection.pollen.title).tag(EnvironmentDetailSection.pollen)
        }
        .pickerStyle(.segmented)
        .padding(6)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
