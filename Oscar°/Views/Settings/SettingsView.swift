//
//  SettingsView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 28.08.21.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  private let settingsService = SettingService.shared
  @State private var showsMemory = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          MemberCard()
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        Section {
          NavigationLink {
            NotificationSettingsView()
          } label: {
            Label("Alerts", systemImage: "bell.badge.fill")
              .labelStyle(.settingsIcon(.red))
          }
          .accessibilityIdentifier("legal.notifications")

          NavigationLink {
            UnitSettings()
          } label: {
            Label("Einheiten", systemImage: "thermometer.medium")
              .labelStyle(.settingsIcon(.orange))
          }

          NavigationLink {
            ForecastSettingsView()
          } label: {
            LabeledContent {
              if settingsService.forecastModelPreference != .bestMatch {
                Text(settingsService.forecastModelPreference.name)
              }
            } label: {
              Label("Vorhersage", systemImage: "calendar")
                .labelStyle(.settingsIcon(.teal))
            }
          }

          NavigationLink {
            AppIconSettingsView()
          } label: {
            Label("App-Symbol", systemImage: "app.grid")
              .labelStyle(.settingsIcon(.blue))
          }

          NavigationLink {
            PermissionSettingsView()
          } label: {
            Label("Berechtigungen", systemImage: "lock.shield.fill")
              .labelStyle(.settingsIcon(.green))
          }
        }

        Section {
          Button {
            dismiss()
            OnboardingCoordinator.shared.replay()
          } label: {
            Label("Einführung erneut ansehen", systemImage: "sparkles")
              .labelStyle(.settingsIcon(.indigo))
          }
        }

        Section {
          SettingsExternalLink(destination: URL(string: "https://oscars.love/")!) {
            Label("Datenschutz", systemImage: "hand.raised.fill")
              .labelStyle(.settingsIcon(.blue))
          }

          SettingsExternalLink(destination: URL(string: "https://oscars.love/")!) {
            Label("Impressum", systemImage: "figure.wave")
              .labelStyle(.settingsIcon(.gray))
          }

          NavigationLink {
            DataSourcesView()
          } label: {
            Label("Datenquellen & Lizenzen", systemImage: "books.vertical.fill")
              .labelStyle(.settingsIcon(.purple))
          }
        } header: {
          Text("Über")
        } footer: {
          aboutFooter
        }
      }
      .navigationTitle("Einstellungen")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(role: .close) {
            dismiss()
          }
        }
      }
      .navigationDestination(isPresented: $showsMemory) {
        MemoryView()
      }
      .task {
        await NotificationSettingsManager.shared.reloadNotificationStatus()
      }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active else { return }
        Task { await NotificationSettingsManager.shared.reloadNotificationStatus() }
      }
    }
  }

  private var aboutFooter: some View {
    VStack(spacing: 2) {
      ProviderLogo(asset: "logo-oscar-cat", height: 44)
        .padding(.bottom, 6)
      Text(verbatim: "Oscar° \(appVersion) (\(appBuild))")
      Text("by Philipp Bolte")
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
    .padding(.top, 12)
    .contentShape(Rectangle())
    .onTapGesture {
      showsMemory = true
    }
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
  }

  private var appBuild: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
  }
}

#Preview {
  SettingsView()
}
