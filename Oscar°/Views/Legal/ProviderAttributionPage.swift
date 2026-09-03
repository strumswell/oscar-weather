import SwiftUI

struct ProviderAttributionPage: View {
    let provider: DataProvider

    var body: some View {
        List {
            Section("Über") {
                Text(LocalizedStringKey(provider.about))
            }
            if let license = provider.license {
                Section("Lizenz") {
                    Text(LocalizedStringKey(license))
                }
            }
            Section("Webseite") {
                ForEach(provider.links) { link in
                    Link(destination: link.url) {
                        Text(LocalizedStringKey(link.title))
                    }
                }
            }
            if !provider.sources.isEmpty {
                Section("Datenquellen") {
                    ForEach(provider.sources) { link in
                        Link(destination: link.url) {
                            Text(LocalizedStringKey(link.title))
                        }
                    }
                }
            }
        }
        .navigationTitle(provider.titleText)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ProviderAttributionPage(provider: DataProvider.all[0])
    }
}
