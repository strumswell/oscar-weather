//
//  LegalView.swift
//  LegalView
//
//  Created by Philipp Bolte on 28.08.21.
//

import SwiftUI
import UserNotifications
import UIKit

struct LegalView: View {
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.presentationMode) var presentationMode

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Spacer(minLength: 0)) {
          MemberCard()
        }
        .listRowBackground(Color(UIColor.systemGroupedBackground))
        .listRowInsets(EdgeInsets())

        Section(header: Text("Einstellungen")) {
          NavigationLink {
            RainAlertSettingsView()
          } label: {
            RainAlertSettingsLabel()
          }

          NavigationLink {
            UnitSettings()
          } label: {
            UnitSettingsLabel()
          }
        }

        Section(header: Text("Über")) {
          HStack {
            Image(systemName: "hand.raised.fill")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.blue)
              .cornerRadius(5)
            Link(
              String(localized: "Datenschutz"), destination: URL(string: "https://oscars.love/")!
            )
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.body)
          }
          HStack {
            Image(systemName: "figure.wave")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.blue)
              .cornerRadius(5)
            Link(String(localized: "Impressum"), destination: URL(string: "https://oscars.love/")!)
              .foregroundColor(colorScheme == .dark ? .white : .black)
              .font(.body)
          }
        }

        Section(header: Text("Services")) {
          NavigationLink {
            OpenMeteoAttribution()
          } label: {
            OpenMeteoLabel()
          }

          NavigationLink {
            BrightSkyAttribution()
          } label: {
            BrightSkyLabel()
          }

          NavigationLink {
            RainViewerAttribution()
          } label: {
            RainViewerLabel()
          }

          NavigationLink {
            DWDAttribution()
          } label: {
            DWDLabel()
          }
        }

        Section(header: Text("Sonstiges")) {
          HStack {
            Image(systemName: "swift")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.red)
              .cornerRadius(5)
            Link(
              "swift-openapi-generator",
              destination: URL(string: "https://github.com/apple/swift-openapi-generator")!
            )
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.body)
          }
          HStack {
            Image(systemName: "swift")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.red)
              .cornerRadius(5)
            Link(
              "swift-openapi-runtime",
              destination: URL(string: "https://github.com/apple/swift-openapi-runtime")!
            )
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.body)
          }
          HStack {
            Image(systemName: "swift")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.red)
              .cornerRadius(5)
            Link(
              "swift-openapi-urlsession",
              destination: URL(string: "https://github.com/apple/swift-openapi-urlsession")!
            )
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.body)
          }
          HStack {
            Image(systemName: "sparkles")
              .frame(width: 30, height: 30)
              .foregroundColor(.white)
              .background(Color.red)
              .cornerRadius(5)
            Link(
              "Icons by Hosein Bagheri",
              destination: URL(
                string: "https://ui8.net/hosein_bagheri/products/3d-weather-icons40")!
            )
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.body)
          }
        }

        NavigationLink {
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
          .padding(.bottom, 1)
        }
      }
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
}

struct LegalView_Previews: PreviewProvider {
  static var previews: some View {
    LegalView()
  }
}

struct RainAlertSettingsView: View {
  @StateObject private var rainAlertManager = RainAlertManager.shared
  @State private var isUpdating = false
  @State private var showPermissionAlert = false

  var body: some View {
    Form {
      Section {
        Toggle(
          String(localized: "Regenwarnungen aktivieren"),
          isOn: Binding(
            get: { rainAlertManager.isEnabled },
            set: { newValue in
              isUpdating = true
              Task {
                if newValue {
                  let enabled = await rainAlertManager.enableAlerts()
                  if !enabled {
                    showPermissionAlert = true
                  }
                } else {
                  await rainAlertManager.disableAlerts()
                }
                isUpdating = false
              }
            }
          )
        )
        .disabled(isUpdating)
      }

      Section {
        Text(statusText)
          .font(.footnote)
          .foregroundColor(.secondary)

        if rainAlertManager.authorizationStatus == .denied {
          Button(String(localized: "Systemeinstellungen öffnen")) {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          }
        }
      }
    }
    .navigationTitle(String(localized: "Regenwarnungen"))
    .navigationBarTitleDisplayMode(.inline)
    .alert(String(localized: "Benachrichtigungen deaktiviert"), isPresented: $showPermissionAlert) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(String(localized: "Erlaube Mitteilungen in den iOS Einstellungen, um Regenwarnungen zu erhalten."))
    }
    .task {
      await rainAlertManager.reloadNotificationStatus()
    }
  }

  private var statusText: String {
    switch rainAlertManager.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return String(localized: "Regenwarnungen werden für deinen aktuellen Ort gesendet.")
    case .denied:
      return String(localized: "Mitteilungen sind auf Systemebene deaktiviert.")
    case .notDetermined:
      return String(localized: "Aktiviere Regenwarnungen, um Mitteilungen bei bevorstehendem Regen zu erhalten.")
    @unknown default:
      return String(localized: "Benachrichtigungsstatus unbekannt.")
    }
  }
}

struct RainAlertSettingsLabel: View {
  var body: some View {
    HStack {
      Image(systemName: "bell.badge.fill")
        .frame(width: 30, height: 30)
        .foregroundColor(.white)
        .background(Color.blue)
        .cornerRadius(5)
      Text(String(localized: "Regenwarnungen"))
    }
  }
}
