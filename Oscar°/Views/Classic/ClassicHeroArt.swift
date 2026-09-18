//
//  ClassicHeroArt.swift
//  Oscar°
//
//  The picture over the top edge of the iOS 6 card: the sim's sun (halo +
//  flare, screen-blended like SunView; the halo only at header size), its
//  phased moon and stars, and one of its cloud wisps drawn once,
//  arranged like the originals. Sized by `width`, so the same composition
//  also serves as the small icon in the hourly strip and the day rows. The
//  sun keeps SunView's blur and screen blend; rain and snow are the sim's
//  StormView boxed under the cloud's belly.
//

import SwiftUI

struct ClassicHeroArt: View {
    let weatherCode: Double
    let isDay: Bool
    let latitude: Double
    /// Card width; the art scales with it.
    let width: CGFloat
    /// Extra shrink for the clouds; the row icons use it because the wide
    /// wisps read as a smear at row size.
    var cloudScale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat { width / 288 }

    private enum Family {
        case clear, partly, cloudy, fog, rain, snow, thunder
    }

    private var family: Family {
        switch weatherCode {
        case 0, 1: .clear
        case 2: .partly
        case 3: .cloudy
        case 45, 48: .fog
        case 71...77, 85, 86: .snow
        case 95...99: .thunder
        default: .rain
        }
    }

    /// Gray for rain, darker for thunder, white otherwise.
    private var cloudTint: Color {
        switch family {
        case .rain: Color(white: 0.72)
        case .thunder: Color(white: 0.5)
        case .snow: Color(white: 0.9)
        default: .white
        }
    }

    var body: some View {
        ZStack {
            if isDay {
                if family == .clear || family == .partly {
                    sun.offset(x: family == .partly ? -40 * scale : 0, y: -6 * scale)
                }
            } else {
                stars
                // A new moon is nothing but a dark disc; leave the stars alone then.
                if family == .clear || family == .partly, MoonPhase.illumination(for: moonPhase) > 0.05 {
                    // Just above the cloud's belly, the lower half behind it,
                    // like the sim's moon peeking out of the deck.
                    moon.offset(x: -40 * scale * cloudScale, y: (28 - 36 * cloudScale) * scale)
                }
            }
            clouds
            precipitation
        }
        // Fixed frame no matter the composition, so rows and strip cells
        // space evenly.
        .frame(width: width, height: 110 * scale)
        .accessibilityHidden(true)
    }

    // MARK: - Precipitation

    /// Rain streaks, snow flakes or a bolt under the clouds; without them a
    /// rainy sky would read as just another overcast one.
    @ViewBuilder
    private var precipitation: some View {
        switch family {
        case .rain:
            storm(.rain)
        case .snow:
            storm(.snow)
        case .thunder:
            storm(.rain)
            Image(systemName: "bolt.fill")
                .font(.system(size: 30 * scale, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                .shadow(color: .yellow.opacity(0.8), radius: 4 * scale)
                .offset(x: 10 * scale, y: 40 * scale)
        default:
            EmptyView()
        }
    }

    /// Where the precipitation box sits (320pt units): below the cloud's
    /// belly (its dense band ends ~67 at header size, ~40 in rows), the
    /// header with a longer fall, the width following the cloud so row
    /// drops don't spawn past its edges.
    private var stormBox: (top: CGFloat, width: CGFloat, height: CGFloat) {
        let height = 45 + 35 * cloudScale
        // The iOS 6 rain symbol is drops only; without a cloud they sit
        // centered in the icon frame.
        let top = isRowRainIcon ? -height / 2 : 15 + 30 * cloudScale
        return (top, 170 * cloudScale, height)
    }

    /// Strip and row rain: the original's symbol had no cloud, only drops.
    private var isRowRainIcon: Bool { cloudScale != 1 && family == .rain }

    /// The header animates; rows and Reduce Motion get a still frame.
    private var animated: Bool { cloudScale == 1 && !reduceMotion }

    /// The sim's storm, boxed under the cloud (320pt units, then scaled as
    /// a whole so the drops shrink with the art). Straight down like the
    /// iOS 6 original.
    private func storm(_ type: Storm.Contents) -> some View {
        let box = stormBox
        // The sim's drops are sized for a full screen; render the header
        // box larger and shrink it so they come out smaller. Rows go the
        // other way: at icon size the plain drops are too fine to see.
        let shrink: CGFloat = cloudScale == 1 ? 1.5 : 0.7
        return StormView(
            type: type,
            direction: .zero,
            strength: type == .snow ? 30 : 45,
            pacing: animated ? .active : .still,
            // Drop speed is per view height; 80pt would crawl.
            speedMultiplier: 3
        )
        .frame(width: box.width * shrink, height: box.height * shrink)
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
        .scaleEffect(scale / shrink)
        .frame(width: box.width * scale, height: box.height * scale)
        .offset(x: -14 * scale * cloudScale, y: (box.top + box.height / 2) * scale)
    }

    // MARK: - Sun

    private var sun: some View {
        ZStack {
            // The halo only carries at header size; at row size it is a blob.
            if cloudScale == 1 {
                Image("halo")
                    .resizable()
                    .frame(width: 200 * scale, height: 200 * scale)
                    .blur(radius: 3 * scale)
                    .opacity(0.9)
            }
            Image("sun")
                .resizable()
                .frame(width: 145 * scale, height: 145 * scale)
                .blur(radius: 2 * scale)
                // The flare is nearly white; screen-blending over navy
                // washes it out further, so push the yellow first.
                .saturation(2.2)
        }
        .blendMode(.screen)
    }

    // MARK: - Moon and stars

    /// Same source as the simulation (the snapshot's `phase` is the day
    /// phase, not the lunar one).
    private var moonPhase: Double { MoonPhase.phaseFraction() }

    /// The sim's moon with its real phase, glow and terminator. Rendered
    /// at the reference size and scaled as a whole so the fixed blur radii
    /// inside MoonView shrink along with it at row size.
    private var moon: some View {
        MoonView(
            phase: moonPhase,
            altitudeProgress: 0.5,
            xFraction: 0.5,
            yFraction: 0.5,
            isSouthernHemisphere: latitude < 0,
            diameter: cloudScale == 1 ? 64 : 50
        )
        .frame(width: 120, height: 120)
        .scaleEffect(scale)
        .frame(width: 120 * scale, height: 120 * scale)
    }

    private var stars: some View {
        StarsView(pacing: .still, opacityOverride: 0.9)
            .frame(width: width * 0.8, height: 96 * scale)
            .mask(
                RadialGradient(colors: [.white, .clear], center: .center, startRadius: 20 * scale, endRadius: 100 * scale)
            )
    }

    // MARK: - Clouds

    /// One cloud image, drawn once, everywhere; only size, tint and opacity
    /// vary by weather, so header and rows stay consistent.
    private static let cloudAsset = "cloud5"

    @ViewBuilder
    private var clouds: some View {
        switch family {
        case .clear:
            EmptyView()
        case .partly:
            wisp(width: 300, x: 16, y: 28, opacity: 0.95)
        case .rain where isRowRainIcon:
            EmptyView()
        case .cloudy, .rain, .snow, .thunder:
            wisp(width: 320, x: -14, y: 14, opacity: 0.95)
        case .fog:
            wisp(width: 320, x: -14, y: 24, opacity: 0.55)
        }
    }

    private func wisp(width: CGFloat, x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        // Explicit height: with scaledToFit alone the 110pt art frame caps
        // every wisp at ~200pt wide and the widths below never apply.
        Image(Self.cloudAsset)
            .resizable()
            .frame(width: width * scale * cloudScale, height: width * 0.55 * scale * cloudScale)
            .colorMultiply(cloudTint)
            .opacity(opacity)
            .offset(x: x * scale * cloudScale, y: y * scale)
    }
}

#Preview {
    VStack(spacing: 30) {
        ClassicHeroArt(weatherCode: 1, isDay: true, latitude: 52, width: 360)
        ClassicHeroArt(weatherCode: 2, isDay: true, latitude: 52, width: 360)
        ClassicHeroArt(weatherCode: 61, isDay: true, latitude: 52, width: 360)
        ClassicHeroArt(weatherCode: 1, isDay: false, latitude: 52, width: 360)
    }
    .background(Color(red: 0.12, green: 0.2, blue: 0.38))
}
