//
//  StationFavoriteStar.swift
//  Oscar°
//

import Charts
import SwiftUI

struct FavoriteStar: View {
    let id: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bursts = 0

    private struct Pop {
        var scale: CGFloat = 1
        var angle: Double = 0
    }

    private static let gold = LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let settings = SettingService.shared
        let isFavorite = settings.favoriteStationIDs.contains(id)
        Button {
            withAnimation(.bouncy) {
                if isFavorite {
                    settings.favoriteStationIDs.removeAll { $0 == id }
                } else {
                    settings.favoriteStationIDs.append(id)
                    bursts += 1
                }
            }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(isFavorite ? AnyShapeStyle(Self.gold) : AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .keyframeAnimator(initialValue: Pop(), trigger: reduceMotion ? 0 : bursts) { content, pop in
                    content.scaleEffect(pop.scale).rotationEffect(.degrees(pop.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(0.7, duration: 0.1)
                        SpringKeyframe(1.45, duration: 0.16, spring: .snappy)
                        SpringKeyframe(1, duration: 0.6, spring: .bouncy(extraBounce: 0.25))
                    }
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(-18, duration: 0.1)
                        SpringKeyframe(14, duration: 0.16, spring: .snappy)
                        SpringKeyframe(0, duration: 0.6, spring: .bouncy(extraBounce: 0.3))
                    }
                }
                .background {
                    if !reduceMotion { StarBurst(trigger: bursts) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Favorit"))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .sensoryFeedback(trigger: settings.favoriteStationIDs) { old, new in
            new.count > old.count ? .impact(flexibility: .soft) : .selection
        }
    }
}

private struct StarBurst: View {
    let trigger: Int

    private struct Spark {
        var distance: CGFloat = 0
        var scale: CGFloat = 0
        var spin: Double = 0
        var fall: CGFloat = 0
        var opacity: Double = 0
    }

    private struct SparkStyle {
        let angle: Double
        let reach: CGFloat
        let delay: Double
        let size: CGFloat
        let isStar: Bool
        let color: Color
    }

    private static let release = 0.1

    private static let sparks: [SparkStyle] = (0..<14).map { index -> SparkStyle in
        let angleJitter: [Double] = [0, 9, -6, 4]
        let reachJitter: [CGFloat] = [0, 5, -3, 7, 2]
        let starSizes: [CGFloat] = [7, 5, 9]
        let dotSizes: [CGFloat] = [3, 2.5, 4]
        let colors: [Color] = [.yellow, .orange, .white]
        let isStar = index.isMultiple(of: 2)
        return SparkStyle(
            angle: Double(index) * 360 / 14 + angleJitter[index % 4],
            reach: (isStar ? 30 : 21) + reachJitter[index % 5],
            delay: Double(index % 3) * 0.03,
            size: (isStar ? starSizes : dotSizes)[index % 3],
            isStar: isStar,
            color: colors[index % 3])
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.yellow.opacity(0.9), .orange.opacity(0)], center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
                .blendMode(.plusLighter)
                .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, glow in
                    content.scaleEffect(glow.scale).opacity(glow.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.3, duration: Self.release)
                        CubicKeyframe(1.3, duration: 0.35)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: Self.release)
                        LinearKeyframe(0.7, duration: 0.05)
                        CubicKeyframe(0, duration: 0.45)
                    }
                }
            ring(delay: 0, size: 30, lineWidth: 2)
            ring(delay: 0.1, size: 40, lineWidth: 1)
            ForEach(Self.sparks.indices, id: \.self) { index in
                spark(Self.sparks[index])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(delay: Double, size: CGFloat, lineWidth: CGFloat) -> some View {
        Circle()
            .stroke(AngularGradient(colors: [.yellow, .orange, .yellow], center: .center), lineWidth: lineWidth)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, ring in
                content.scaleEffect(ring.scale).opacity(ring.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.4, duration: Self.release + delay)
                    CubicKeyframe(1.5, duration: 0.5)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: Self.release + delay)
                    LinearKeyframe(0.9, duration: 0.04)
                    CubicKeyframe(0, duration: 0.46)
                }
            }
    }

    private func spark(_ style: SparkStyle) -> some View {
        let start = Self.release + style.delay
        return Group {
            if style.isStar {
                Image(systemName: "star.fill").font(.system(size: style.size))
            } else {
                Circle().frame(width: style.size, height: style.size)
            }
        }
        .foregroundStyle(style.color)
        .shadow(color: .orange.opacity(0.7), radius: 2)
        .keyframeAnimator(initialValue: Spark(), trigger: trigger) { content, spark in
            content
                .scaleEffect(spark.scale)
                .rotationEffect(.degrees(spark.spin))
                .offset(y: -spark.distance)
                .rotationEffect(.degrees(style.angle))
                .offset(y: spark.fall)
                .opacity(spark.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.distance) {
                LinearKeyframe(4, duration: start)
                SpringKeyframe(style.reach, duration: 0.5, spring: .snappy)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0, duration: start)
                SpringKeyframe(1, duration: 0.18, spring: .bouncy)
                CubicKeyframe(0.1, duration: 0.5)
            }
            KeyframeTrack(\.spin) {
                LinearKeyframe(0, duration: start)
                CubicKeyframe(style.isStar ? 160 : 0, duration: 0.7)
            }
            KeyframeTrack(\.fall) {
                LinearKeyframe(0, duration: start + 0.25)
                CubicKeyframe(9, duration: 0.45)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: start)
                LinearKeyframe(1, duration: 0.03)
                LinearKeyframe(1, duration: 0.32)
                LinearKeyframe(0, duration: 0.35)
            }
        }
    }
}
