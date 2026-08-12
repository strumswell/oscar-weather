import SwiftUI

struct HourlyDetailSegmentedControl: View {
    @Binding var selectedSection: HourlyDetailSection

    var body: some View {
        Picker("Stündliche Details", selection: $selectedSection) {
            ForEach(HourlyDetailSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(6)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
