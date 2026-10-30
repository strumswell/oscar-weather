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
  @Bindable private var settingsService = SettingService.shared
  private let supporter = SupporterStore.shared
  @State private var showsMemory = false
  @State private var cardEditorTab: MemberCardEditor.Tab?
  @State private var cardStyle = MemberStatus.current().style
  @AppStorage(CatNeeds.enabledKey) private var catEnabled = true

  var body: some View {
    NavigationStack {
      List {
        Section {
        } header: {
          MemberCard(editorTab: $cardEditorTab, style: $cardStyle)
            .padding(.top, 18)
            .textCase(nil)
            .listRowInsets(EdgeInsets())
        }
        .listSectionMargins(.top, 0)

        Section("Club") {
          NavigationLink {
            SupportView()
          } label: {
            LabeledContent {
              if supporter.isSupporter {
                Text("Danke")
              }
            } label: {
              Label {
                Text("Oscar unterstützen")
              } icon: {
                Image(systemName: "heart.fill")
                  .overlay(alignment: .topTrailing) {
                    HeartSparkle()
                      .offset(x: 4, y: -4)
                  }
              }
              .labelStyle(.settingsIcon(.pink))
            }
          }
          .accessibilityIdentifier("settings.support")

          NavigationLink {
            StatsView()
          } label: {
            Label("Statistik", systemImage: "chart.bar.fill")
              .labelStyle(.settingsIcon(.indigo))
          }

          NavigationLink {
            ClubVoucherView()
          } label: {
            Label("Einlösen", systemImage: "ticket.fill")
              .labelStyle(.settingsIcon(cardStyle.accent))
          }
        }

        Section("Wetter") {
          NavigationLink {
            NotificationSettingsView()
          } label: {
            Label("Benachrichtigungen", systemImage: "bell.badge.fill")
              .labelStyle(.settingsIcon(.red))
          }
          .accessibilityIdentifier("settings.alerts")

          NavigationLink {
            ForecastSettingsView()
          } label: {
            LabeledContent {
              if settingsService.forecastModelPreference != .bestMatch {
                Text(settingsService.forecastModelPreference.name)
              }
            } label: {
              Label("Vorhersage", systemImage: "calendar")
                .labelStyle(.settingsIcon(.blue))
            }
          }
          .accessibilityIdentifier("settings.forecast")

          NavigationLink {
            UnitSettings()
          } label: {
            Label("Einheiten", systemImage: "thermometer.medium")
              .labelStyle(.settingsIcon(.orange))
          }

          NavigationLink {
            PermissionSettingsView()
          } label: {
            Label("Berechtigungen", systemImage: "lock.shield.fill")
              .labelStyle(.settingsIcon(.green))
          }
        }

        Section("Darstellung") {
          NavigationLink {
            NowLayoutSettingsView()
          } label: {
            Label("Ansicht anpassen", systemImage: "rectangle.stack")
              .labelStyle(.settingsIcon(.purple))
          }
          .accessibilityIdentifier("settings.layout")

          // A Mac running the iPad app can't swap its icon.
          if UIApplication.shared.supportsAlternateIcons {
            NavigationLink {
              AppIconSettingsView()
            } label: {
              Label("App-Symbol", systemImage: "app.grid")
                .labelStyle(.settingsIcon(.blue))
            }
          }

          NavigationLink {
            CatSettingsView()
          } label: {
            LabeledContent {
              if !catEnabled {
                Text("Aus")
              }
            } label: {
              Label { Text(verbatim: "Oscar") } icon: { Image(systemName: "cat.fill") }
                .labelStyle(.settingsIcon(.brown))
            }
          }
          .accessibilityIdentifier("settings.cat")

          if supporter.isSupporter || settingsService.classicTheme {
            Toggle(isOn: $settingsService.classicTheme) {
              classicThemeLabel
            }
          } else {
            NavigationLink {
              SupportView()
            } label: {
              LabeledContent {
                Image(systemName: "lock.fill")
              } label: {
                classicThemeLabel
              }
            }
            .accessibilityValue(Text("Für Unterstützer:innen"))
          }
        }

        Section {
          Button {
            dismiss()
            OnboardingCoordinator.shared.replay()
          } label: {
            Label("Einführung erneut ansehen", systemImage: "sparkles")
              .labelStyle(.settingsIcon(.teal))
          }
          .tint(.primary)

          SettingsExternalLink(destination: URL(string: "https://oscars.love/privacy")!) {
            Label("Datenschutz", systemImage: "hand.raised.fill")
              .labelStyle(.settingsIcon(.blue))
          }

          SettingsExternalLink(destination: URL(string: "https://oscars.love/impressum")!) {
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
      .scrollContentBackground(.hidden)
      .background {
        Color(.systemGroupedBackground)
          .ignoresSafeArea()
        MemberCardGlow(style: cardStyle)
      }
      .navigationTitle("Einstellungen")
      .toolbarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            Haptics.land()
            cardEditorTab = .stickers
          } label: {
            Image(systemName: "creditcard.rewards")
          }
          .accessibilityLabel(Text("Karte bearbeiten"))
          .accessibilityIdentifier("settings.memberCard.edit")
        }
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

  private var classicThemeLabel: some View {
    Label("Klassisch", systemImage: "clock.arrow.circlepath")
      .labelStyle(.settingsIcon(.gray))
  }

  private var aboutFooter: some View {
    VStack(spacing: 2) {
      ProviderLogo(asset: "logo-oscar-cat", height: 44)
        .opacity(0.7)
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
