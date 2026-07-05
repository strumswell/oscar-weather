//
//  AppIconSettingsView.swift
//  Oscar°
//
//  Created by Codex on 09.05.26.
//

import SwiftUI
import UIKit

struct AppIconSettingsView: View {
    @State private var selectedIconName = UIApplication.shared.alternateIconName
    @State private var iconChangeError: String?
    @State private var isChangingIcon = false

    var body: some View {
        List {
            ForEach(AppIconCatalog.sections) { section in
                Section(String(localized: section.title)) {
                    ForEach(section.icons) { icon in
                        Button {
                            Task {
                                await select(icon)
                            }
                        } label: {
                            AppIconRow(
                                icon: icon,
                                isSelected: selectedIconName == icon.alternateIconName
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isChangingIcon)
                        .accessibilityLabel(Text(icon.name))
                        .accessibilityValue(
                            selectedIconName == icon.alternateIconName
                                ? Text("Ausgewählt")
                                : Text("")
                        )
                    }
                }
            }

            Section {
                Text("app_icon_ai_disclosure")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App-Symbol")
        .navigationBarTitleDisplayMode(.inline)
        .alert("App-Symbol konnte nicht geändert werden", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                iconChangeError = nil
            }
        } message: {
            if let iconChangeError {
                Text(iconChangeError)
            }
        }
        .onAppear {
            selectedIconName = UIApplication.shared.alternateIconName
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { iconChangeError != nil },
            set: { isPresented in
                if !isPresented {
                    iconChangeError = nil
                }
            }
        )
    }

    @MainActor
    private func select(_ icon: AppIconOption) async {
        selectedIconName = UIApplication.shared.alternateIconName
        guard selectedIconName != icon.alternateIconName else { return }
        guard !isChangingIcon else { return }

        guard UIApplication.shared.supportsAlternateIcons else {
            iconChangeError = String(localized: "app_icon_error_unsupported")
            return
        }

        isChangingIcon = true

        do {
            try await AppIconChangeService.setIcon(icon.alternateIconName)
            await finishSelecting(icon)
        } catch {
            showIconChangeError(error, icon: icon)
        }
    }

    @MainActor
    private func finishSelecting(_ icon: AppIconOption) async {
        try? await Task.sleep(for: .milliseconds(350))
        selectedIconName = UIApplication.shared.alternateIconName
        isChangingIcon = false

        if selectedIconName == icon.alternateIconName {
            UIApplication.shared.playHapticFeedback()
        }
    }

    @MainActor
    private func showIconChangeError(_ error: Error, icon: AppIconOption) {
        selectedIconName = UIApplication.shared.alternateIconName
        isChangingIcon = false

        iconChangeError = AppIconChangeService.errorMessage(for: error, icon: icon, currentIconName: selectedIconName)
    }
}

private enum AppIconChangeService {
    @MainActor
    static func setIcon(_ alternateIconName: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(alternateIconName)
    }

    static func errorMessage(for error: Error, icon: AppIconOption, currentIconName: String?) -> String {
        let nsError = error as NSError
        let currentIcon = currentIconName ?? String(localized: "Original")

        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 35 {
            return String(
                format: String(localized: "app_icon_error_system_prompt_unavailable"),
                currentIcon
            )
        }

        return String(
            format: String(localized: "app_icon_error_change_failed"),
            String(localized: icon.name),
            currentIcon,
            error.localizedDescription,
            nsError.domain,
            nsError.code
        )
    }
}

private struct AppIconRow: View {
    let icon: AppIconOption
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconPreview(assetName: icon.previewAssetName)

            Text(icon.name)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.bold())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct AppIconPreview: View {
    let assetName: String

    var body: some View {
        Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.tertiary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

struct AppIconSettingsLabel: View {
    var body: some View {
        HStack {
            Image(systemName: "app.grid")
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text("App-Symbol")
        }
    }
}

#Preview {
    NavigationStack {
        AppIconSettingsView()
    }
}
