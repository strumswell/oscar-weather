//
//  DataSourcesView.swift
//  Oscar°
//

import SwiftUI

struct DataSourcesView: View {
  var body: some View {
    List {
      Section("Wetterdaten") {
        NavigationLink {
          OpenMeteoAttribution()
        } label: {
          OpenMeteoLabel()
        }

        NavigationLink {
          DWDAttribution()
        } label: {
          DWDLabel()
        }

        NavigationLink {
          OperaAttribution()
        } label: {
          OperaLabel()
        }

        NavigationLink {
          NOAAAttribution()
        } label: {
          NOAALabel()
        }

        NavigationLink {
          CwaAttribution()
        } label: {
          CwaLabel()
        }

        NavigationLink {
          RedemetAttribution()
        } label: {
          RedemetLabel()
        }

        NavigationLink {
          AemetAttribution()
        } label: {
          AemetLabel()
        }

        NavigationLink {
          EcccAttribution()
        } label: {
          EcccLabel()
        }

        SettingsExternalLink(destination: URL(string: "https://imo.net/resources/calendar/")!) {
          Label {
            Text(verbatim: "International Meteor Organization (IMO)")
          } icon: {
            Image(systemName: "sparkles")
          }
          .labelStyle(.settingsIcon(.cyan))
        }

        SettingsExternalLink(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
          Label("Kartendaten © OpenStreetMap", systemImage: "map.fill")
            .labelStyle(.settingsIcon(.teal))
        }

        SettingsExternalLink(destination: URL(string: "https://openfreemap.org")!) {
          Label {
            Text(verbatim: "Kartenkacheln: OpenFreeMap")
          } icon: {
            Image(systemName: "square.grid.3x3.fill")
          }
          .labelStyle(.settingsIcon(.cyan))
        }
      }

      Section("Open Source") {
        SettingsExternalLink(destination: URL(string: "https://github.com/apple/swift-openapi-generator")!) {
          Label {
            Text(verbatim: "swift-openapi-generator")
          } icon: {
            Image(systemName: "swift")
          }
          .labelStyle(.settingsIcon(.orange))
        }

        SettingsExternalLink(destination: URL(string: "https://github.com/apple/swift-openapi-runtime")!) {
          Label {
            Text(verbatim: "swift-openapi-runtime")
          } icon: {
            Image(systemName: "swift")
          }
          .labelStyle(.settingsIcon(.orange))
        }

        SettingsExternalLink(destination: URL(string: "https://github.com/apple/swift-openapi-urlsession")!) {
          Label {
            Text(verbatim: "swift-openapi-urlsession")
          } icon: {
            Image(systemName: "swift")
          }
          .labelStyle(.settingsIcon(.orange))
        }

        SettingsExternalLink(destination: URL(string: "https://ui8.net/hosein_bagheri/products/3d-weather-icons40")!) {
          Label {
            Text(verbatim: "Icons by Hosein Bagheri")
          } icon: {
            Image(systemName: "sparkles")
          }
          .labelStyle(.settingsIcon(.pink))
        }
      }
    }
    .navigationTitle("Datenquellen & Lizenzen")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    DataSourcesView()
  }
}
