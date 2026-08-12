import SwiftUI

struct MeteorShowerDetailView: View {
    let event: MeteorShowerEvent

    @Environment(Weather.self) private var weather
    @Environment(\.dismiss) private var dismiss

    private var response: MeteorShowerResponse? {
        weather.meteorShowerResponse
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    introduction
                    detailRows
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle(MeteorShowerCopy.showerName(for: event))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: { dismiss() })
                }
            }
            .containerBackground(.clear, for: .navigation)
        }
    }

    private var introduction: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            Text(MeteorShowerCopy.detailExplanation(for: event.presentation))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            if let status = MeteorShowerCopy.detailPeakText(
                status: event.status,
                presentation: event.presentation
            ) {
                row(
                    label: statusLabel,
                    value: status
                )
                Divider().padding(.leading, 16)
            }
            row(
                label: String(localized: "meteor.detail.activity", defaultValue: "Aktivität"),
                value: String.localizedStringWithFormat(
                    String(
                        localized: "meteor.detail.zhrFormat",
                        defaultValue: "Bis zu %lld pro Stunde unter idealen Bedingungen"
                    ),
                    Int64(event.zhr)
                )
            )
            Divider().padding(.leading, 16)
            if let visibility = MeteorShowerCopy.visibilityText(
                for: event.visibility.classification
            ) {
                row(
                    label: String(
                        localized: "meteor.detail.astronomicalVisibility",
                        defaultValue: "Astronomische Sichtbarkeit"
                    ),
                    value: visibility
                )
                Divider().padding(.leading, 16)
            }
            if let cloudCover = observingCloudCover {
                row(
                    label: String(
                        localized: "meteor.detail.cloudCoverAtBestTime",
                        defaultValue: "Bewölkung zur Beobachtungszeit"
                    ),
                    value: "\(Int(cloudCover.rounded())) %"
                )
                Divider().padding(.leading, 16)
            }
            if let darkness {
                row(
                    label: String(localized: "meteor.detail.darkness", defaultValue: "Dunkelheit"),
                    value: darkness
                )
                Divider().padding(.leading, 16)
            }
            row(
                label: String(localized: "meteor.detail.source", defaultValue: "Quelle"),
                value: sourceName
            )
        }
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var darkness: String? {
        guard let timeZoneID = response?.location?.timezone,
              let timeZone = TimeZone(identifier: timeZoneID),
              let start = response?.night?.darknessStart,
              let end = response?.night?.darknessEnd else {
            return nil
        }
        return "\(SettingService.formattedTime(start, timeZone: timeZone)) – \(SettingService.formattedTime(end, timeZone: timeZone))"
    }

    private var observingCloudCover: Double? {
        guard let target = event.visibility.bestTime ?? response?.night?.darknessStart,
              let times = weather.forecast.hourly?.time,
              let cloudCover = weather.forecast.hourly?.cloudcover else {
            return nil
        }
        return MeteorShowerForecast.cloudCover(
            nearestTo: target,
            timestamps: times,
            values: cloudCover
        )
    }

    private var sourceName: String {
        event.source.uppercased() == "IMO"
            ? "International Meteor Organization (IMO)"
            : event.source
    }

    private var statusLabel: String {
        let peakPresentations = ["many_tonight", "peak_tonight", "near_peak"]
        let peakStatuses = ["peak", "near_peak"]
        if peakPresentations.contains(event.presentation.lowercased())
            || peakStatuses.contains(event.status.lowercased()) {
            return String(localized: "meteor.detail.peak", defaultValue: "Höhepunkt")
        }
        return String(localized: "meteor.detail.status", defaultValue: "Status")
    }

    private func row(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
