import CoreLocation
import SwiftUI

/// "Webcams": live images near the place, nearest first. Loads when the section shows up,
/// never in the background (Windy's terms forbid scanning, and image URLs expire after
/// 10 min). Hidden when there are none or the server has no Windy key.
struct WebcamsView: View {
    @Environment(Location.self) private var location
    @Environment(Weather.self) private var weather
    @State private var webcams: [Components.Schemas.Webcam] = []
    @State private var selected: Components.Schemas.Webcam?

    var body: some View {
        let timeZone = weather.forecast.locationTimeZone
        VStack(alignment: .leading) {
            if webcams.isEmpty {
                // Something must appear for the task to run.
                Color.clear.frame(height: 0)
            } else {
                NowSectionHeader { Text("Webcams") }
                    .padding(.bottom)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(webcams.prefix(8)) { webcam in
                            WebcamTile(webcam: webcam, from: location.coordinates, timeZone: timeZone) {
                                selected = webcam
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                WebcamCredit()
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
        }
        // Keyed on the rounded coordinate that is sent, so GPS drift doesn't refetch.
        .task(id: "\(LocationService.outboundCoordinate(location.coordinates))") {
            webcams = (try? await APIClient.shared.getWebcams(near: location.coordinates)) ?? []
        }
        .sheet(item: $selected) { webcam in
            WebcamSheet(webcam: webcam, timeZone: timeZone)
        }
    }
}

private struct WebcamTile: View {
    let webcam: Components.Schemas.Webcam
    let from: CLLocationCoordinate2D
    let timeZone: TimeZone
    let onSelect: () -> Void

    var body: some View {
        let km = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: webcam.latitude, longitude: webcam.longitude)) / 1000
        let detail = "\(km.formatted(.number.precision(.fractionLength(0)))) km · \(webcam.updated_at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))"
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                WebcamImage(url: webcam.preview_url)
                    .frame(width: WebcamImage.tileSize.width, height: WebcamImage.tileSize.height)
                    .clipShape(.rect(cornerRadius: 12))
                    .cardBorder(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: webcam.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(width: WebcamImage.tileSize.width, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(webcam.title), \(detail)"))
        .accessibilityHint(Text("Öffnet die Webcam"))
    }
}

/// One webcam large: the preview, when it was taken, and today's timelapse on windy.com.
/// Shared by the forecast section and the map.
struct WebcamSheet: View {
    let webcam: Components.Schemas.Webcam
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WebcamImage(url: webcam.preview_url)
                .aspectRatio(WebcamImage.previewSize, contentMode: .fit)
                // Windy's terms allow the original size or smaller, never stretched.
                .frame(maxWidth: WebcamImage.previewSize.width)
                .clipShape(.rect(cornerRadius: 12))
            Text(verbatim: webcam.title)
                .font(.headline)
            Text("Aufgenommen \(webcam.updated_at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let player = webcam.player_url.flatMap(URL.init(string:)) {
                Link("Zeitraffer von heute", destination: player)
                    .font(.body.weight(.semibold))
            }
            Spacer(minLength: 0)
            WebcamCredit()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Windy's image or a quiet placeholder while it loads (or after its URL expired).
private struct WebcamImage: View {
    static let previewSize = CGSize(width: 400, height: 224)
    /// Half the preview, so the image is never upscaled on a 2x screen.
    static let tileSize = CGSize(width: 200, height: 112)

    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
    }
}

/// The acknowledgment Windy's terms require next to every webcam, in their wording and with
/// both links, so it stays English in every language.
struct WebcamCredit: View {
    private static let text = (try? AttributedString(markdown:
        "Webcams provided by [windy.com](https://www.windy.com) - [add new webcam](https://www.windy.com/webcams/add)"))
        ?? AttributedString("Webcams provided by windy.com")

    var body: some View {
        Text(Self.text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
