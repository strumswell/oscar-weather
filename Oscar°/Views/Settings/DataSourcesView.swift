//
//  DataSourcesView.swift
//  Oscar°
//

import SwiftUI

struct DataSourcesView: View {
  var body: some View {
    List {
      Section("Wetterdaten") {
        ForEach(DataProvider.all) { provider in
          NavigationLink {
            ProviderAttributionPage(provider: provider)
          } label: {
            ProviderRow(provider: provider)
          }
        }

        SettingsExternalLink(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
          Label("Kartendaten © OpenStreetMap", systemImage: "map.fill")
            .labelStyle(.settingsIcon(.teal))
        }

        SettingsExternalLink(destination: URL(string: "https://openfreemap.org")!) {
          Label {
            Text("Kartenkacheln: OpenFreeMap")
          } icon: {
            Image(systemName: "square.grid.3x3.fill")
          }
          .labelStyle(.settingsIcon(.cyan))
        }
      }

      Section("Open Source") {
        ForEach(Self.openSourceLinks, id: \.title) { link in
          SettingsExternalLink(destination: URL(string: link.url)!) {
            Label {
              Text(verbatim: link.title)
            } icon: {
              Image(systemName: link.icon)
            }
            .labelStyle(.settingsIcon(link.tint))
          }
        }
      }
    }
    .navigationTitle("Datenquellen & Lizenzen")
    .navigationBarTitleDisplayMode(.inline)
  }

  private static let openSourceLinks: [(title: String, url: String, icon: String, tint: Color)] = [
    ("swift-openapi-generator", "https://github.com/apple/swift-openapi-generator", "swift", .orange),
    ("swift-openapi-runtime", "https://github.com/apple/swift-openapi-runtime", "swift", .orange),
    ("swift-openapi-urlsession", "https://github.com/apple/swift-openapi-urlsession", "swift", .orange),
    ("Icons by Hosein Bagheri", "https://ui8.net/hosein_bagheri/products/3d-weather-icons40", "sparkles", .pink),
  ]
}

#Preview {
  NavigationStack {
    DataSourcesView()
  }
}
