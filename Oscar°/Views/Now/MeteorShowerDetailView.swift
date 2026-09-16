import SwiftUI

struct MeteorShowerDetailView: View {
    let event: MeteorShowerEvent

    @Environment(Weather.self) private var weather
    @Environment(\.dismiss) private var dismiss
    @State private var observingDate = Date.now

    private var response: MeteorShowerResponse? { weather.meteorShowerResponse }

    /// Follows refreshed data for the same shower while the sheet stays open.
    private var shower: MeteorShowerEvent? {
        response?.showers.first { $0.id == event.id }
    }

    private var timeZone: TimeZone {
        weather.forecast.locationTimeZone
    }

    private var isExpired: Bool {
        response.map { $0.validUntil <= observingDate } ?? true
    }

    private var nextExpiry: Date? {
        [response?.validUntil, shower?.bestWindow?.start, shower?.bestWindow?.end]
            .compactMap { $0 }.filter { $0 > observingDate }.min()
    }

    private var bestWindow: MeteorShowerWindow? {
        guard !isExpired, let window = shower?.bestWindow,
              window.start < window.end, window.end > observingDate else { return nil }
        return window
    }

    private var observingCondition: String {
        guard let shower else { return "unavailable" }
        guard let window = shower.bestWindow, window.end > observingDate else { return "unobservable" }
        return isExpired ? "unavailable" : shower.condition
    }

    /// Weather provenance describes the server's overall best window only.
    private var weatherSources: [String] {
        guard let response, let bestWindow, response.bestWindow?.shower == event.id,
              bestWindow.cloudCover != nil || bestWindow.precipitationMmH != nil else { return [] }
        return MeteorShowerCopy.weatherSourceNames(for: response.weather)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introduction
                    observingDetails
                    showerDetails
                    sources
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("meteor.detail")
            .navigationTitle(MeteorShowerCopy.showerName(for: event.id))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismiss() })
                        .accessibilityIdentifier("meteor.detail.close")
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
        .task(id: nextExpiry) {
            // Re-evaluate at the next deadline even if the sheet stays open.
            // The task is cancelled automatically when the sheet is dismissed.
            observingDate = .now
            guard let nextExpiry else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, nextExpiry.timeIntervalSinceNow)))
                observingDate = .now
            } catch {
                return
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MeteorShowerEmblem(size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(MeteorShowerCopy.observingConditionText(for: observingCondition))
                        .font(.headline)
                    Text(MeteorShowerCopy.observingExplanation(for: observingCondition))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if observingCondition == "unavailable" {
                Label(
                    String(localized: "meteor.detail.staleNotice", defaultValue: "Ein Teil der Daten konnte nicht aktualisiert werden. Die Einschätzung kann sich ändern."),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var observingDetails: some View {
        if let bestWindow {
            VStack(spacing: 0) {
                row(
                    label: bestWindow.cloudCover == nil
                        ? String(localized: "meteor.detail.astronomicalWindow", defaultValue: "Astronomisches Beobachtungsfenster")
                        : String(localized: "meteor.detail.bestTime", defaultValue: "Beste Beobachtungszeit"),
                    value: intervalText(start: bestWindow.start, end: bestWindow.end)
                )
                Text(String(localized: "meteor.detail.localTime", defaultValue: "Ortszeit am gewählten Standort"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                if let cloudCover = bestWindow.cloudCover, cloudCover.isFinite {
                    Divider().padding(.horizontal, 16)
                    row(
                        label: String(localized: "meteor.detail.cloudCoverAtBestTime", defaultValue: "Bewölkung zur Beobachtungszeit"),
                        value: "\(Int(min(100, max(0, cloudCover)).rounded())) %"
                    )
                }
                if bestWindow.moonIllumination.isFinite {
                    Divider().padding(.horizontal, 16)
                    row(
                        label: String(localized: "meteor.detail.moon", defaultValue: "Mond zur Beobachtungszeit"),
                        value: String.localizedStringWithFormat(
                            String(localized: "meteor.detail.moonIlluminationFormat", defaultValue: "%lld %% beleuchtet"),
                            Int64((min(1, max(0, bestWindow.moonIllumination)) * 100).rounded())
                        )
                    )
                }
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var showerDetails: some View {
        VStack(spacing: 0) {
            let rows = showerRows
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 {
                    Divider().padding(.horizontal, 16)
                }
                row(label: rows[index].label, value: rows[index].value)
            }
            if (shower ?? event).isPeakEstimated {
                Text(String(localized: "meteor.detail.annualEstimate", defaultValue: "Der Höhepunkt ist eine jährliche Schätzung. Der tatsächliche Zeitpunkt kann um einen Tag oder mehr abweichen."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 18))
    }

    private var showerRows: [(label: String, value: String)] {
        let current = shower ?? event
        let phase = MeteorShowerPhase.of(current, night: response?.night, now: observingDate)
        var rows: [(label: String, value: String)] = [
            (statusLabel(for: phase, estimated: current.isPeakEstimated),
             MeteorShowerCopy.detailPeakText(for: phase)),
        ]
        if let zhr = MeteorShowerCatalogue.typicalZHR[current.id.uppercased()], zhr > 0 {
            rows.append((
                String(localized: "meteor.detail.activity", defaultValue: "Aktivität"),
                String.localizedStringWithFormat(
                    String(localized: "meteor.detail.idealRateFormat", defaultValue: "Bis zu %@ pro Stunde unter idealen Bedingungen"),
                    zhr.formatted()
                )
            ))
        }
        if let bestWindow, bestWindow.radiantAltitude.isFinite {
            rows.append((
                String(localized: "meteor.detail.radiantAltitude", defaultValue: "Höhe des Radianten"),
                "\(Int(bestWindow.radiantAltitude.rounded()))°"
            ))
        }
        if let start = response?.night.darknessStart, let end = response?.night.darknessEnd, end > start {
            rows.append((
                String(localized: "meteor.detail.darkness", defaultValue: "Dunkelheit"),
                intervalText(start: start, end: end)
            ))
        }
        return rows
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String.localizedStringWithFormat(
                String(localized: "meteor.detail.astronomySourceFormat", defaultValue: "Astronomie: %@"),
                "International Meteor Organization (IMO)"
            ))
            if !weatherSources.isEmpty {
                Text(String.localizedStringWithFormat(
                    String(localized: "meteor.detail.weatherSourceFormat", defaultValue: "Wetter: %@"),
                    weatherSources.formatted(.list(type: .and))
                ))
                Text(String(localized: "meteor.detail.derivedClassification", defaultValue: "Die Beobachtungsbedingungen werden aus Wetter- und Astronomiedaten abgeleitet."))
            }
            Text(String(localized: "meteor.detail.observingTip", defaultValue: "Ein dunkler Ort abseits von Straßenlaternen verbessert die Sicht. Die tatsächliche Zahl sichtbarer Sternschnuppen kann deutlich niedriger sein."))
                .padding(.top, 3)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private func statusLabel(for phase: MeteorShowerPhase, estimated: Bool) -> String {
        guard phase != .active else {
            return String(localized: "meteor.detail.status", defaultValue: "Status")
        }
        return estimated
            ? String(localized: "meteor.detail.estimatedPeak", defaultValue: "Geschätzter Höhepunkt")
            : String(localized: "meteor.detail.peak", defaultValue: "Höhepunkt")
    }

    private func intervalText(start: Date, end: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.timeZone = timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startTime = SettingService.formattedTime(start, timeZone: timeZone)
        let endTime = SettingService.formattedTime(end, timeZone: timeZone)
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(dateFormatter.string(from: start)) · \(startTime) – \(endTime)"
        }
        return "\(dateFormatter.string(from: start)) · \(startTime) –\n\(dateFormatter.string(from: end)) · \(endTime)"
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
