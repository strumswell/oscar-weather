//
//  LegalView.swift
//  LegalView
//
//  Created by Philipp Bolte on 28.08.21.
//

import SwiftUI
import UIKit

struct LegalView: View {
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          MemberCard()
            .padding(.horizontal, 16)

          section("Einstellungen") {
            settingsNavigationLink {
              NotificationSettingsView()
            } label: {
              NotificationSettingsLabel()
            }

            Divider()

            settingsNavigationLink {
              UnitSettings()
            } label: {
              UnitSettingsLabel()
            }
          }

          section("Über") {
            legalLinkRow(
              systemImage: "hand.raised.fill",
              iconBackground: .blue,
              title: String(localized: "Datenschutz"),
              destination: URL(string: "https://oscars.love/")!
            )

            Divider()

            legalLinkRow(
              systemImage: "figure.wave",
              iconBackground: .blue,
              title: String(localized: "Impressum"),
              destination: URL(string: "https://oscars.love/")!
            )
          }

          section("Services") {
            settingsNavigationLink {
              OpenMeteoAttribution()
            } label: {
              OpenMeteoLabel()
            }

            Divider()

            settingsNavigationLink {
              BrightSkyAttribution()
            } label: {
              BrightSkyLabel()
            }

            Divider()

            settingsNavigationLink {
              RainViewerAttribution()
            } label: {
              RainViewerLabel()
            }

            Divider()

            settingsNavigationLink {
              DWDAttribution()
            } label: {
              DWDLabel()
            }

            Divider()

            settingsNavigationLink {
              NOAAAttribution()
            } label: {
              NOAALabel()
            }
          }

          section("Sonstiges") {
            legalLinkRow(
              systemImage: "swift",
              iconBackground: .red,
              title: "swift-openapi-generator",
              destination: URL(string: "https://github.com/apple/swift-openapi-generator")!
            )

            Divider()

            legalLinkRow(
              systemImage: "swift",
              iconBackground: .red,
              title: "swift-openapi-runtime",
              destination: URL(string: "https://github.com/apple/swift-openapi-runtime")!
            )

            Divider()

            legalLinkRow(
              systemImage: "swift",
              iconBackground: .red,
              title: "swift-openapi-urlsession",
              destination: URL(string: "https://github.com/apple/swift-openapi-urlsession")!
            )

            Divider()

            legalLinkRow(
              systemImage: "sparkles",
              iconBackground: .red,
              title: "Icons by Hosein Bagheri",
              destination: URL(string: "https://ui8.net/hosein_bagheri/products/3d-weather-icons40")!
            )
          }

          settingsNavigationLink {
            MemoryView()
              .navigationBarBackButtonHidden()
          } label: {
            HStack {
              Spacer()
              VStack {
                Text("Oscar° Weather")
                  .font(.body)
                  .bold()
                Text("by Philipp Bolte")
                  .font(.caption)
                  .padding(.bottom, 2)
              }
              Spacer()
            }
            .padding(.vertical, 12)
          }
          .padding(.horizontal, 16)
          .background(sectionBackground)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
      }
      .background(Color(UIColor.systemGroupedBackground))
      .navigationBarTitle("Rechtliches", displayMode: .inline)
      .toolbar(content: {
        ToolbarItem(
          placement: .navigationBarTrailing,
          content: {
            Button(
              "Fertig",
              action: {
                presentationMode.wrappedValue.dismiss()
                UIApplication.shared.playHapticFeedback()
              })
          })
      })
    }
  }

  @ViewBuilder
  private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)

      VStack(spacing: 0) {
        content()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 4)
      .background(sectionBackground)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .padding(.horizontal, 16)
    }
  }

  private func legalLinkRow(
    systemImage: String,
    iconBackground: Color,
    title: String,
    destination: URL
  ) -> some View {
    HStack {
      Image(systemName: systemImage)
        .frame(width: 30, height: 30)
        .foregroundStyle(.white)
        .background(iconBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

      Link(title, destination: destination)
        .foregroundStyle(colorScheme == .dark ? .white : .black)
        .font(.body)

      Spacer()
    }
    .padding(.vertical, 12)
  }

  private func settingsNavigationLink<Destination: View, Label: View>(
    @ViewBuilder destination: () -> Destination,
    @ViewBuilder label: () -> Label
  ) -> some View {
    NavigationLink {
      destination()
    } label: {
      HStack {
        label()
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(.primary)

        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
      .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
    .tint(.primary)
  }

  private var sectionBackground: Color {
    Color(UIColor.secondarySystemGroupedBackground)
  }
}

struct LegalView_Previews: PreviewProvider {
  static var previews: some View {
    LegalView()
  }
}
