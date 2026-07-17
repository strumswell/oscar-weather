//
//  LocationCard.swift
//  Oscar°
//
//  A saved location as a card: a static miniature of the weather simulation
//  showing the place's current sky, with name, label emoji, and temperature.
//

import SwiftUI

struct LocationCard: View {
    let title: String
    var detail: String?
    var emoji: String?
    var temperature: Double?
    var snapshot: AtmosphereSnapshot?
    var isSelected = false
    var isDefault = false
    var isCurrentLocation = false
    /// True while the list is on another tab or under a sheet: the backdrop's
    /// precipitation layer would otherwise keep animating unseen.
    var backdropPaused = false

    // The card grows with Dynamic Type so title/detail keep fitting.
    @ScaledMetric(relativeTo: .headline) private var cardHeight: CGFloat = 102
    @ScaledMetric(relativeTo: .title) private var temperatureFontSize: CGFloat = 36

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                if hasBadge {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.16))
                            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                        badgeContent
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow.opacity(0.95))
                                .accessibilityHidden(true)
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(temperature.map { "\(Int($0.rounded()))°" } ?? "--°")
                    .font(.system(size: temperatureFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(temperature == nil ? 0.4 : 1))
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.5), value: temperature)
            }
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        // The backdrop renders at a FIXED width (screen width covers every card)
        // so edit mode's width change only moves the clip edge over it. Sized to
        // the card instead, the shader/canvas layers snap to the target width
        // while the container is still animating.
        .background(alignment: .leading) {
            LocationSimBackdrop(snapshot: snapshot, paused: backdropPaused)
                .overlay(
                    // Bottom-weighted scrim so white text stays readable on bright skies.
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.12), location: 0),
                            .init(color: .black.opacity(0.26), location: 0.45),
                            .init(color: .black.opacity(0.45), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: UIScreen.main.bounds.width, height: cardHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    .white.opacity(isSelected ? 0.75 : 0.12),
                    lineWidth: isSelected ? 1.75 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black.opacity(0.65), .white)
                    .padding(9)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .animation(.spring(duration: 0.35), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(isSelected ? Text("Ausgewählt") : Text(""))
    }

    private var hasBadge: Bool {
        (emoji?.isEmpty == false) || isCurrentLocation
    }

    @ViewBuilder
    private var badgeContent: some View {
        if let emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 24))
        } else if isCurrentLocation {
            Image(systemName: "location.fill")
                // Fixed size: .body grows past the 44pt badge circle at
                // accessibility text sizes.
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
    }

    private var accessibilityText: Text {
        var parts = [title]
        if let detail { parts.append(detail) }
        if let temperature { parts.append("\(Int(temperature.rounded())) Grad") }
        if isDefault { parts.append(String(localized: "Standardort")) }
        return Text(parts.joined(separator: ", "))
    }
}

/// Near-static rendering of the weather sim for one card, composed from the
/// live simulation's primitives — the same pattern as the onboarding dioramas.
/// Sky, stars, and clouds hold a single frame (`.still`); falling rain/snow is
/// the one layer that animates, so a wet card reads as weather, not a photo.
/// Without a snapshot it shows the calm twilight the app also uses before any
/// data arrives.
struct LocationSimBackdrop: View {
    var snapshot: AtmosphereSnapshot?
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snap = snapshot ?? .twilight

        GeometryReader { proxy in
            ZStack {
                AtmosphereSkyShaderView(snapshot: snap, size: proxy.size, pacing: .still)

                let starOpacity = Double(snap.nightAmount) * Double(1 - snap.cloudCoverage * 0.85)
                if starOpacity > 0.05 {
                    StarsView(pacing: .still, opacityOverride: starOpacity)
                }

                if snap.sunDiscVisibility > 0.01 && snap.cloudDensity < 0.82 && snap.precipitationIntensity < 0.55 {
                    SunView(progress: Double(snap.timeOfDay))
                        .opacity(Double((1 - snap.cloudDensity * 0.45) * snap.phase * snap.sunDiscVisibility))
                }

                if snap.cloudDensity + snap.cloudCoverage > 0.02 {
                    CloudsView(
                        thickness: cloudThickness(for: snap),
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snap),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snap),
                        pacing: .still
                    )
                }

                if max(snap.precipitationIntensity, snap.snowfallIntensity) > 0.001 {
                    StormView(
                        type: snap.condition == .snow ? .snow : .rain,
                        direction: .degrees(0),
                        strength: stormStrength(for: snap),
                        pacing: reduceMotion || paused ? .still : .active,
                        // Drop speed is per view height; at card height the
                        // unscaled fall reads as slow motion.
                        speedMultiplier: 3
                    )
                    .opacity(0.75)
                }
            }
        }
        .background(AtmosphereSampler.skyGradient(snapshot: snap))
        .allowsHitTesting(false)
    }

    /// Same coverage → deck mapping as the full simulation.
    private func cloudThickness(for snapshot: AtmosphereSnapshot) -> Cloud.Thickness {
        switch snapshot.cloudCoverage {
        case ..<0.08: .none
        case ..<0.25: .thin
        case ..<0.45: .light
        case ..<0.68: .regular
        case ..<0.92: .thick
        default: .ultra
        }
    }

    /// Fewer frozen drops than the live sim; a card only needs the impression.
    private func stormStrength(for snapshot: AtmosphereSnapshot) -> Int {
        let isSnow = snapshot.condition == .snow
        let intensity = Double(isSnow ? snapshot.snowfallIntensity : snapshot.precipitationIntensity)
        return max(10, min(90, Int(25 + intensity * 80)))
    }
}

/// Press feedback for card rows: a gentle shrink, no gray highlight.
struct LocationCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 12) {
        LocationCard(
            title: "Zuhause",
            detail: "Leipzig · Klar",
            emoji: "🏠",
            temperature: 21.4,
            snapshot: .fallback,
            isSelected: true,
            isDefault: true
        )
        LocationCard(
            title: "Aktueller Standort",
            detail: "Gewitter",
            temperature: 17.2,
            snapshot: .onboardingStorm,
            isCurrentLocation: true
        )
        LocationCard(
            title: "Oma",
            detail: "Hessen",
            emoji: "👵",
            temperature: nil,
            snapshot: .onboardingNight
        )
    }
    .padding()
    .background(Color.black)
    .environment(Weather.mock)
}
