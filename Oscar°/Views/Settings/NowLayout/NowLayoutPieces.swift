//
//  NowLayoutPieces.swift
//  Oscar°
//

import SwiftUI

// MARK: - Pieces

struct LayoutFrame: Identifiable {
    let id: Int
    let title: LocalizedStringResource?
    let size: CGSize

    var form: LayoutForm { LayoutForm.of(size) }
    var isWide: Bool { form.isWide }

    private static let wideWindowKey = "wideWindowSize"

    @MainActor static var device: [LayoutFrame] {
        let screen = (UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)?.screen
        // nativeBounds is portrait whatever the orientation.
        let portrait = screen.map { CGSize(width: $0.nativeBounds.width / $0.nativeScale, height: $0.nativeBounds.height / $0.nativeScale) }
            ?? CGSize(width: 402, height: 874)
        let landscape: CGSize? = if UIDevice.current.userInterfaceIdiom == .pad {
            CGSize(width: portrait.height, height: portrait.width)
        } else if let stored = UserDefaults.standard.array(forKey: wideWindowKey) as? [Double], stored.count == 2 {
            CGSize(width: stored[0], height: stored[1])
        } else {
            nil
        }
        guard let landscape else { return [LayoutFrame(id: 0, title: nil, size: portrait)] }
        return [
            LayoutFrame(id: 0, title: "Hochkant", size: portrait),
            LayoutFrame(id: 1, title: "Quer", size: landscape),
        ]
    }

    // The Duo's open display has no API while it is folded; the forecast's widest window stands in.
    static func rememberWideWindow(_ size: CGSize) {
        guard size.width >= WideForecast.minWidth, size.width > size.height else { return }
        UserDefaults.standard.set([size.width, size.height], forKey: wideWindowKey)
    }
}

struct ColumnID: Hashable {
    enum Side {
        case page, stage, feed

        var onStage: Bool? {
            switch self {
            case .page: nil
            case .stage: true
            case .feed: false
            }
        }

        var title: LocalizedStringResource? {
            switch self {
            case .page: nil
            case .stage: "Bühne"
            case .feed: "Verlauf"
            }
        }
    }

    let frame: Int
    let side: Side
}

struct BlockID: Hashable {
    let column: ColumnID
    let section: NowSection
}

enum DropTarget: Equatable {
    case dock
    case column(ColumnID, index: Int)
}

struct SectionDrag {
    let section: NowSection
    let source: Int?
    let location: CGPoint
    let target: DropTarget?
}

struct SectionBlock: View {
    let section: NowSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if section != .map {
                Text(section.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(.leading)
            }
            card
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(section.title))
    }

    @ViewBuilder
    private var card: some View {
        switch section {
        case .map:
            Color.clear
                .frame(height: 260)
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
        case .radar:
            PrecipitationSeriesChart(points: OnboardingSampleData.showerPoints, timeZone: .current)
                .padding(16)
                .frame(height: 120)
                .cardBackground()
                .clipShape(.rect(cornerRadius: 10))
                .cardBorder()
                .padding(.horizontal)
        case .hourly:
            strip(spacing: 12) {
                ForEach(OnboardingSampleData.hourlyItems.prefix(5)) { HourlyForecastCard(item: $0) }
            }
        case .daily:
            CollageDailyCard(dayCount: 3)
                .padding(.horizontal)
        case .stations:
            StationsCard(stations: Array(OnboardingSampleData.stations.prefix(1)), timeZone: .current) { _ in }
                .padding(.horizontal)
        case .environment:
            strip(spacing: 14) {
                ForEach(OnboardingSampleData.gauges) { AQIGaugeCard(metric: $0) }
            }
        case .climate:
            CollageClimateCard()
                .padding(.horizontal)
        }
    }

    private func strip(spacing: CGFloat, @ViewBuilder cards: () -> some View) -> some View {
        HStack(spacing: spacing, content: cards)
            .font(.system(size: 18))
            .fixedSize()
            .padding(.leading)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }
}

struct Callout: View {
    static let height: CGFloat = 20

    let section: NowSection
    let screenSide: HorizontalEdge

    var body: some View {
        HStack(spacing: 6) {
            if screenSide == .leading { line }
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(section.tint.gradient, in: .rect(cornerRadius: 5))
            Text(section.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if screenSide == .trailing { line }
        }
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .shadow(radius: 2)
        .contentShape(Rectangle().inset(by: -6))
    }

    private var line: some View {
        Rectangle()
            .frame(width: 16, height: 1)
            .opacity(0.6)
    }
}

struct DockChip: View {
    let section: NowSection

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: section.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(section.tint.gradient, in: .rect(cornerRadius: 11))
            Text(section.title)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 64)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
