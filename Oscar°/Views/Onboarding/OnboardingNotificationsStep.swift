//
//  OnboardingNotificationsStep.swift
//  Oscar°
//

import SwiftUI

/// Only where oscar-server has alert coverage: pick which alerts to get while
/// a thunderstorm rages in the hero window. Each choice shows a preview of
/// what will actually arrive. Confirming requests the system permission and
/// enrolls through NotificationSettingsManager.
struct OnboardingNotificationsStep: View {
    let onContinue: () -> Void

    @Environment(Location.self) private var location
    @State private var rainAlerts = true
    @State private var liveRain = true
    @State private var weatherAlerts = true
    @State private var enabling = false
    @State private var appeared = false

    private var anySelected: Bool { rainAlerts || weatherAlerts }

    /// The person's own place when one is known: GPS name first, then the
    /// city picked on the manual step.
    private var place: String {
        if !location.name.isEmpty { return location.name }
        return LocationService.shared.city.getSelectedCity()?.label ?? "Leipzig"
    }

    var body: some View {
        OnboardingStageLayout(layout: .list) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            OnboardingStepIcon(systemImage: "bell.badge.fill", tint: .red, wiggles: true)
                            Text("Wann soll sich Oscar melden?")
                                .font(.onboardingTitle)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .onboardingEntrance(appeared, delay: 0.1)

                        VStack(spacing: 22) {
                            NotificationChoice(title: "Regen", isOn: $rainAlerts) {
                                NotificationBanner(
                                    title: "Regen zieht auf",
                                    message: Text("Leichter Regen in \(place) ab \(SampleTimes.rainStart, format: .dateTime.hour().minute()), voraussichtlich bis \(SampleTimes.rainEnd, format: .dateTime.hour().minute()).")
                                )
                            }

                            NotificationChoice(title: "Unwetterwarnungen", isOn: $weatherAlerts) {
                                NotificationBanner(
                                    title: "Amtliche Warnung vor Gewitter",
                                    message: Text("Gewitter mit Starkregen möglich. Gültig bis \(SampleTimes.warningEnd, format: .dateTime.hour().minute()). (\(place))")
                                )
                            }

                            if RainRadarLiveActivityManager.isSupported {
                                NotificationChoice(
                                    title: "Regen auf dem Sperrbildschirm",
                                    detail: "Schon bevor es losgeht, live mit jedem Radarbild.",
                                    isOn: $liveRain
                                ) {
                                    LiveActivityPreview(place: place)
                                }
                                // Same rule as Settings: the Live Activity rides on rain alerts.
                                .disabled(!rainAlerts)
                            }
                        }
                        .onboardingEntrance(appeared, delay: 0.2)
                    }
                    .padding(.horizontal, OnboardingStage.edgePadding)
                    .padding(.top, OnboardingStage.canvasInset)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                // Previews that run on below fade out instead of cutting off at the buttons.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 28)
                    }
                }

                OnboardingButtonStack(
                    primaryTitle: anySelected ? "Mitteilungen erlauben" : "Weiter",
                    primaryDisabled: enabling,
                    primaryAction: confirm,
                    secondaryTitle: anySelected ? "Keine Mitteilungen" : nil,
                    secondaryAction: onContinue
                )
                .onboardingEntrance(appeared, delay: 0.3)
            }
        }
        .onAppear { appeared = true }
    }

    /// Turns on what was picked. The first call raises the system prompt and
    /// registers with APNs/oscar-server; the rest reuse that answer. A denied
    /// prompt simply moves on.
    private func confirm() {
        guard !enabling else { return }
        enabling = true

        Task {
            let manager = NotificationSettingsManager.shared
            var granted = true
            if rainAlerts {
                granted = await manager.setRainAlertsEnabled(true)
            }
            if granted, weatherAlerts {
                granted = await manager.setWeatherAlertsEnabled(true)
            }
            if granted, rainAlerts, liveRain {
                _ = await manager.setLiveRainStatusEnabled(true)
            }
            enabling = false
            onContinue()
        }
    }
}

/// A toggle with a preview of what it sends underneath; the preview fades to
/// gray while the choice is off. The optional detail renders as the toggle's
/// subtitle.
private struct NotificationChoice<Preview: View>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    @Binding var isOn: Bool
    @ViewBuilder let preview: Preview

    @Environment(\.isEnabled) private var isEnabled

    private var isActive: Bool { isOn && isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                }
            }
            preview
                .opacity(isActive ? 1 : 0.35)
                .saturation(isActive ? 1 : 0)
                .animation(.smooth, value: isActive)
                .accessibilityHidden(true)
        }
    }
}

/// Times for the previews, a few minutes ahead of when the step first shows.
private enum SampleTimes {
    static let rainStart = minutesFromNow(15)
    static let rainEnd = minutesFromNow(55)
    static let warningEnd = minutesFromNow(240)

    /// On a five-minute mark, like real alerts read.
    private static func minutesFromNow(_ minutes: Double) -> Date {
        let step = 5.0 * 60
        let now = Date.now.timeIntervalSinceReferenceDate
        let mark = (now / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: mark + minutes * 60)
    }
}

/// A look-alike of an iOS notification banner.
private struct NotificationBanner: View {
    let title: LocalizedStringKey
    let message: Text

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image("AppIconOriginalPreview")
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("jetzt")
                        .foregroundStyle(.secondary)
                }
                message
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16))
    }
}

/// The rain Live Activity's Lock Screen card as it really lays out: place and
/// radar stamp, headline, subline, the peak ahead as the hero value, and the
/// hour as bars. Rain is expected, so the first bars are dry.
private struct LiveActivityPreview: View {
    let place: String

    private static let bars: [Double] = [
        0, 0, 0, 0, 0, 0.1, 0.25, 0.45, 0.6, 0.55, 0.75, 1,
        0.9, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.12, 0.05, 0, 0, 0,
    ]
    private static let peak = 1.2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.rain.fill")
                        Text(verbatim: place)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(SampleTimes.rainStart.addingTimeInterval(-15 * 60), format: .dateTime.hour().minute())
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    Text("Leichter Regen ab \(SampleTimes.rainStart, format: .dateTime.hour().minute())")
                        .font(.title3.weight(.semibold))
                        .padding(.top, 2)
                    Text("voraussichtlich bis \(SampleTimes.rainEnd, format: .dateTime.hour().minute())")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: -2) {
                    Text(Self.peak, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 40, weight: .regular))
                        .monospacedDigit()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.4, green: 0.7, blue: 1))
                            .frame(width: 6, height: 6)
                        Text(verbatim: "mm/h")
                        Text("max.")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .fixedSize()
            }

            VStack(spacing: 3) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Self.bars.indices, id: \.self) { index in
                        Capsule()
                            .fill(Self.bars[index] > 0 ? Color(red: 0.4, green: 0.7, blue: 1) : .white.opacity(0.2))
                            .frame(height: max(3, 36 * Self.bars[index]))
                    }
                }
                .frame(height: 36, alignment: .bottom)

                HStack {
                    Text("Jetzt")
                    Spacer()
                    Text(SampleTimes.rainEnd, format: .dateTime.hour().minute())
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingStage.navy, in: .rect(cornerRadius: 24))
    }
}

#Preview {
    ZStack {
        OnboardingSceneView(scene: .storm)
        OnboardingStage(layout: .list)
        OnboardingNotificationsStep {}
    }
    .environment(Weather.mock)
    .environment(Location())
}
