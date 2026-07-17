//
//  LocationPreviewSheet.swift
//  Oscar°
//
//  Forecast preview for a place that is not saved yet: the real simulation
//  and the Now screen's hourly/daily sections over a private Weather
//  instance, with cancel/add actions. Detail navigation stays inert — the
//  sheet answers "how is it there", the Now screen owns the deep dives.
//

import CoreLocation
import SwiftUI

struct LocationPreviewSheet: View {
    let candidate: LocationCandidate
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weather = Weather()
    @State private var previewLocation: Location
    @State private var presentation = NowPresentationCoordinator()
    @State private var loadFailed = false
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureFontSize: CGFloat = 96
    private let client = APIClient.shared

    init(candidate: LocationCandidate, onAdd: @escaping () -> Void) {
        self.candidate = candidate
        self.onAdd = onAdd
        let location = Location()
        location.coordinates = candidate.coordinate
        location.name = candidate.name
        _previewLocation = State(initialValue: location)
    }

    var body: some View {
        ZStack {
            WeatherSimulationView()

            if weather.hasContent {
                ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                        header
                            .padding(.top, 36)
                            .padding(.bottom, 28)
                        RainView()
                        HourlyView()
                        DailyView()
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Vorhersage nicht verfügbar", systemImage: "cloud.slash")
                } description: {
                    Text("Die Wetterdaten konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.")
                } actions: {
                    Button("Erneut versuchen") {
                        loadFailed = false
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: weather.hasContent)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .presentationDragIndicator(.visible)
        .environment(weather)
        .environment(previewLocation)
        .environment(presentation)
        .task {
            await load()
        }
    }

    // Deliberately spare: place name and temperature only — the sim and the
    // hourly/daily sections below carry the condition.
    private var header: some View {
        VStack(spacing: 4) {
            Text(candidate.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(UIColor.label))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(roundTemperatureString(temperature: weather.forecast.current?.temperature))
                .font(.system(size: temperatureFontSize))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Color(UIColor.label))
                .contentTransition(.numericText())
                .padding(.top, 2)
        }
        .shadow(radius: 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Abbrechen")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Button {
                onAdd()
            } label: {
                Label("Hinzufügen", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func load() async {
        do {
            async let radarTask = client.getRadarSeries(coordinates: candidate.coordinate)
            let forecast = try await client.getForecast(coordinates: candidate.coordinate)
            weather.forecast = forecast
            weather.precipSeries = (try? await radarTask) ?? nil
            weather.updateTime()
            weather.lastUpdated = .now
            weather.loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }
}

#Preview {
    LocationPreviewSheet(
        candidate: LocationCandidate(
            name: "Leipzig",
            detail: "Sachsen, Deutschland",
            latitude: 51.34,
            longitude: 12.38
        )
    ) {}
}
