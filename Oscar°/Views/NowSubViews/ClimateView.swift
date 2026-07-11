//
//  ClimateView.swift
//  Oscar°
//
//  A chart-free "Klima" section: today's high placed on an 85-year timeline for the user's
//  location, expressed as plain language plus an Ed-Hawkins warming-stripes ribbon. Sits below
//  the "Umwelt" section and taps through to ClimateDetailView.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class ClimateModel {
    enum Phase {
        case idle
        case loading
        /// Blocked on the archive rate limiter (cold fetch over the per-minute budget).
        case throttled
        case loaded
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var summary: ClimateSummary?
    /// Identity (coords | day | high) of the summary currently shown.
    private var loadedKey: String?
    /// Coordinates of the last load. The card is blanked to its placeholder only when *this*
    /// changes (a real location switch), so a same-location refresh or midnight rollover updates
    /// in place instead of flashing the placeholder.
    private var loadedCoordsKey: String?
    /// Identity currently being fetched, so a refresh-triggered reload doesn't restart an in-flight
    /// (possibly expensive cold) fetch for the same inputs.
    private var inFlightKey: String?
    /// Bumped per load so a superseded one can't overwrite newer state — both the throttle callback
    /// and the result/failure assignment check it.
    private var loadGeneration = 0

    /// `identity` encodes the inputs (coords | calendar day | today's high); the view re-runs this
    /// whenever any of them change, and also on each weather refresh (to retry a failed/stale load).
    func load(latitude: Double, longitude: Double, todayHigh: Double?, identity: String) async {
        // Skip an unresolved location (the section is hosted only once the forecast has content,
        // so this is essentially the pre-first-load instant).
        guard latitude != 0 || longitude != 0 else { return }

        // Already showing a current summary for these exact inputs, or already loading them.
        if (identity == loadedKey && summary != nil) || identity == inFlightKey { return }

        let coordsKey = String(format: "%.2f,%.2f", latitude, longitude)
        if coordsKey != loadedCoordsKey { summary = nil }
        loadedCoordsKey = coordsKey

        if summary == nil { phase = .loading }
        loadGeneration &+= 1
        let generation = loadGeneration
        inFlightKey = identity
        defer { if inFlightKey == identity { inFlightKey = nil } }

        do {
            let result = try await ClimateArchiveStore.shared.summary(
                latitude: latitude,
                longitude: longitude,
                today: .now,
                todayHigh: todayHigh
            ) { [weak self] in
                Task { @MainActor in
                    guard let self, self.loadGeneration == generation else { return }
                    if self.summary == nil { self.phase = .throttled }
                }
            }
            // A newer load (location / day / high changed) superseded this one — don't clobber it.
            guard generation == loadGeneration else { return }
            if let result {
                summary = result
                loadedKey = identity
                phase = .loaded
            } else {
                // No usable data yet. Leave loadedKey unset so a later refresh retries; hide the
                // section if there's nothing to show, else keep the last-good summary.
                phase = summary == nil ? .failed : .loaded
            }
        } catch is CancellationError {
            // Superseded by a newer load; it will drive state.
        } catch {
            guard generation == loadGeneration else { return }
            phase = summary == nil ? .failed : .loaded
        }
    }
}

struct ClimateView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var model = ClimateModel()

    private var latitude: Double { weather.forecast.latitude ?? 0 }
    private var longitude: Double { weather.forecast.longitude ?? 0 }

    private var unit: ClimateTemperatureUnit {
        ClimateTemperatureUnit(settingValue: SettingService.resolvedTemperatureUnit)
    }

    /// Today's forecast high, converted to °C to match the ERA5 history (the forecast comes back
    /// in the user's unit). Used as the live current-year point since ERA5 lags ~5 days.
    private var todayHighCelsius: Double? {
        guard let high = weather.forecast.daily?.temperature_2m_max?.first else { return nil }
        return unit.celsius(fromValue: high)
    }

    /// Recompute identity: changes when the location, the calendar day (midnight rollover → a new
    /// "this day"), or today's high changes — so the section never shows a stale day/value.
    private var loadIdentity: String {
        let coords = String(format: "%.2f,%.2f", latitude, longitude)
        let day = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let high = todayHighCelsius.map { String(Int($0.rounded())) } ?? "nil"
        return "\(coords)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)|\(high)"
    }

    var body: some View {
        Group {
            if (latitude == 0 && longitude == 0) || model.phase == .failed {
                // No location yet, or the archive is unavailable for this spot: stay invisible
                // rather than leaving a broken-looking gap.
                EmptyView()
            } else {
                VStack(alignment: .leading) {
                    Text("Klima")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.primary)
                        .padding([.leading, .bottom])
                        .padding(.top, 30)

                    content
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                .scrollTransition { content, phase in
                    content
                        .opacity(phase.isIdentity ? 1 : 0.8)
                        .scaleEffect(phase.isIdentity ? 1 : 0.99)
                        .blur(radius: phase.isIdentity ? 0 : 0.5)
                }
            }
        }
        .task(id: loadIdentity) {
            await model.load(
                latitude: latitude, longitude: longitude,
                todayHigh: todayHighCelsius, identity: loadIdentity)
        }
        .task(id: weather.lastUpdated) {
            // A weather refresh (incl. returning to foreground): retry if the section failed earlier
            // or is still on a previous day's data. Lifecycle-bound like the load above, and a no-op
            // when already current or in flight — so it never interrupts the expensive cold fetch
            // (which the primary task owns) and is cancelled with the view.
            await model.load(
                latitude: latitude, longitude: longitude,
                todayHigh: todayHighCelsius, identity: loadIdentity)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let summary = model.summary, model.phase == .loaded {
            Button {
                presentDetail(summary)
            } label: {
                ClimateSummaryCard(summary: summary, unit: unit)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Klima. \(climateHeadline(summary)) \(climateStatLine(summary, unit))"))
            .accessibilityHint(Text("Öffnet Klimadetails"))
            .accessibilityIdentifier("now.climate")
        } else {
            ClimatePlaceholder(isThrottled: model.phase == .throttled)
        }
    }

    private func presentDetail(_ summary: ClimateSummary) {
        UIApplication.shared.playHapticFeedback()
        presentation.present(.climate(summary))
    }
}

// MARK: - Card

struct ClimateSummaryCard: View {
    let summary: ClimateSummary
    let unit: ClimateTemperatureUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(climateHeadline(summary))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let analog = climateAnalogLine(summary, unit) {
                Text(analog)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                WarmingStripesRibbon(stripes: summary.allStripes, sigma: summary.standardDeviation)
                ClimateTimeAxis(firstYear: summary.firstYear, todayYear: summary.todayYear)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                Text("Heute \(summary.anomalyString(unit))")
                Spacer(minLength: 4)
                Text("Normal \(summary.normalString(unit))")
                Spacer(minLength: 4)
                Text("Rekord \(summary.previousWarmRecordString(unit)) (\(String(summary.previousWarmRecord.year)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Warming stripes ribbon

struct WarmingStripesRibbon: View {
    let stripes: [ClimateStripe]
    let sigma: Double
    var height: CGFloat = 54
    var cornerRadius: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            guard !stripes.isEmpty else { return }
            let stripeWidth = size.width / CGFloat(stripes.count)
            for (index, stripe) in stripes.enumerated() {
                let x = CGFloat(index) * stripeWidth
                // Overdraw a hair so adjacent fills don't leave hairline seams.
                let rect = CGRect(x: x, y: 0, width: stripeWidth + 0.75, height: size.height)
                context.fill(
                    Path(rect),
                    with: .color(ClimateStripeColor.color(anomaly: stripe.anomaly, sigma: sigma)))
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Time axis

/// Decade labels under the ribbon, each placed at its true year position. The first year sits flush
/// left and "heute" flush right; interior labels are the 20-year marks that fit, dropping any within
/// 8 years of an endpoint so nothing collides.
struct ClimateTimeAxis: View {
    let firstYear: Int
    let todayYear: Int

    // Scale the row height with the caption2 metric so the labels don't clip at large Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var axisHeight: CGFloat = 13

    private struct Tick: Identifiable {
        let id: Int
        let isToday: Bool
        let fraction: Double
    }

    private var ticks: [Tick] {
        let span = Double(max(todayYear - firstYear, 1))
        var result = [Tick(id: firstYear, isToday: false, fraction: 0)]
        let start = ((firstYear + 8) / 20 + 1) * 20
        for year in stride(from: start, through: todayYear - 8, by: 20)
        where year > firstYear && year < todayYear {
            result.append(Tick(id: year, isToday: false, fraction: Double(year - firstYear) / span))
        }
        result.append(Tick(id: todayYear, isToday: true, fraction: 1))
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(ticks) { tick in
                    label(for: tick)
                        .fixedSize()
                        // Center the label on its year, clamped so the end labels stay fully on-screen.
                        .alignmentGuide(.leading) { dimensions in
                            let center = tick.fraction * width
                            let leading = min(
                                max(center - dimensions.width / 2, 0),
                                max(width - dimensions.width, 0))
                            return -leading
                        }
                        .alignmentGuide(.top) { _ in 0 }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(height: axisHeight)
    }

    @ViewBuilder
    private func label(for tick: Tick) -> some View {
        if tick.isToday {
            Text("heute")
        } else {
            Text(verbatim: "\(tick.id)")
        }
    }
}

// MARK: - Color legend

/// "kühler ▭▭▭ wärmer" — a small blue→red gradient key for the stripe colors.
struct ClimateLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("kühler als normal")
            Capsule()
                .fill(
                    LinearGradient(
                        colors: ClimateStripeColor.legendGradient,
                        startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 6)
            Text("wärmer als normal")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement()
        .accessibilityLabel(Text("Farbskala von kühler als normal (blau) bis wärmer als normal (rot)."))
    }
}

// MARK: - Interactive ribbon (detail view: scrub to read a year's value)

struct InteractiveClimateRibbon: View {
    let stripes: [ClimateStripe]
    let sigma: Double
    let unit: ClimateTemperatureUnit
    var height: CGFloat = 96

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                callout(width: geometry.size.width)
            }
            .frame(height: 22)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .topLeading) {
                    WarmingStripesRibbon(stripes: stripes, sigma: sigma, height: height, cornerRadius: 14)
                    if let index = selectedIndex, stripes.indices.contains(index) {
                        Rectangle()
                            .fill(.white)
                            .frame(width: 2, height: height)
                            .overlay(Rectangle().stroke(.black.opacity(0.35), lineWidth: 0.5))
                            .position(x: centerX(for: index, width: width), y: height / 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectedIndex = index(forX: value.location.x, width: width)
                        }
                        .onEnded { _ in selectedIndex = nil }
                )
            }
            .frame(height: height)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Verlauf der Tageshöchstwerte"))
        .accessibilityValue(accessibilityValueText)
        .accessibilityAdjustableAction { direction in
            guard !stripes.isEmpty else { return }
            let current = selectedIndex ?? stripes.count - 1
            switch direction {
            case .increment: selectedIndex = min(current + 1, stripes.count - 1)
            case .decrement: selectedIndex = max(current - 1, 0)
            @unknown default: break
            }
        }
    }

    /// VoiceOver reads the focused year and its high, defaulting to the most recent (today) before
    /// any scrub. Pairs with the adjustable action so swiping up/down steps through the years — the
    /// drag-to-scrub gesture itself isn't operable under VoiceOver.
    private var accessibilityValueText: Text {
        guard !stripes.isEmpty else { return Text(verbatim: "") }
        let index = min(max(selectedIndex ?? stripes.count - 1, 0), stripes.count - 1)
        let stripe = stripes[index]
        let temperature = Int(unit.value(fromCelsius: stripe.value).rounded())
        return Text(verbatim: "\(stripe.year), \(temperature)°")
    }

    /// Only shown while actively scrubbing; clears when the finger lifts.
    @ViewBuilder
    private func callout(width: CGFloat) -> some View {
        if let index = selectedIndex, stripes.indices.contains(index) {
            let stripe = stripes[index]
            let temperature = Int(unit.value(fromCelsius: stripe.value).rounded())
            let half: CGFloat = 52
            HStack(spacing: 6) {
                Circle()
                    .fill(ClimateStripeColor.color(anomaly: stripe.anomaly, sigma: sigma))
                    .frame(width: 8, height: 8)
                Text(verbatim: "\(stripe.year) · \(temperature)°")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.15), lineWidth: 0.5))
            .position(
                x: min(max(centerX(for: index, width: width), half), max(width - half, half)),
                y: 11)
        }
    }

    private func centerX(for index: Int, width: CGFloat) -> CGFloat {
        guard !stripes.isEmpty else { return 0 }
        let stripeWidth = width / CGFloat(stripes.count)
        return (CGFloat(index) + 0.5) * stripeWidth
    }

    private func index(forX x: CGFloat, width: CGFloat) -> Int {
        guard !stripes.isEmpty, width > 0 else { return 0 }
        let stripeWidth = width / CGFloat(stripes.count)
        return min(max(Int(x / stripeWidth), 0), stripes.count - 1)
    }
}

// MARK: - Loading placeholder

struct ClimatePlaceholder: View {
    let isThrottled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 15)
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 190, height: 13)
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)).frame(height: 54)
                .overlay {
                    if isThrottled { ProgressView().tint(.secondary) }
                }
            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 230, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.08), lineWidth: 1)
        }
    }
}
