//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct TomorrowAttribution: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Über")) {
                    Text("Tomorrow.io, vertreten durch die Tomorrow Companies Inc., stellt diverse Kartenlayer unter deren Free-Tier bereit. Darunter fallen unter anderem das globale Regenradar, Temperatur, Windgeschwindigkeit, Windrichtung, Wolken und Luftfeuchtigkeit.")
                }
                Section(header: Text("Webseite")) {
                    Link(destination: URL(string: "https://www.tomorrow.io/company/")!, label: {
                        Text("tomorrow.io")
                    })
                }
            }
        }
        .navigationBarTitle("Tomorrow", displayMode: .inline)
    }
}

struct TomorrowLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "map.fill")
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(5)
            Text("Tomorrow")
        }
    }
}

#Preview {
    TomorrowAttribution()
}
