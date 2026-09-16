import SwiftUI

protocol DetailSection: CaseIterable, Hashable, Identifiable where AllCases: RandomAccessCollection {
    var title: LocalizedStringKey { get }
}

/// The segmented switch above the detail sheets' paged sections.
struct DetailSectionPicker<Section: DetailSection>: View {
    let label: LocalizedStringKey
    @Binding var selection: Section

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(Section.allCases) { section in
                Text(section.title).tag(section)
            }
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
