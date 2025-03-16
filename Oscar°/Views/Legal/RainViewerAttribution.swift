//
//  RainViewerAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct RainViewerAttribution: View {
  var body: some View {
    NavigationView {
      List {
        Section(header: Text("Über")) {
          Text(
            "RainViewer stellt diverse Kartenlayer bereit. Darunter fallen unter anderem das globale Regenradar und Satellitenbilder."
          )
        }
        Section(header: Text("Webseite")) {
          Link(
            destination: URL(string: "https://www.rainviewer.com/")!,
            label: {
              Text("rainviewer.com")
            })
        }
      }
    }
    .navigationBarTitle("RainViewer", displayMode: .inline)
  }
}

struct RainViewerLabel: View {
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    HStack {
      Image(systemName: "cloud.rain.fill")
        .frame(width: 30, height: 30)
        .foregroundColor(.white)
        .background(.green)
        .cornerRadius(5)
      Text("RainViewer")
    }
  }
}

#Preview {
  RainViewerAttribution()
}
