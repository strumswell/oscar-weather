import CoreLocation
import SwiftUI

struct DailyDetailView: View {
  @Environment(Location.self) private var location: Location
  @Environment(\.dismiss) private var dismiss
  private let settingsService = SettingService.shared

  @State private var detailModel = DetailModel()
  @State private var selectedSection: DailyDetailSection = .temperature
  @State private var dismissalFeedback = false

  private var points: [DailyEnsembleDayPoint] {
    detailModel.response?.dayPoints ?? []
  }

  private var windSpeedSetting: WindSpeedUnit {
    WindSpeedUnit(settingValue: settingsService.settings?.windSpeedUnit)
  }

  private var windPoints: [DailyEnsembleDayPoint] {
    guard windSpeedSetting.usesBeaufortDisplay else { return points }
    return points.map { $0.convertingWindSpeedsToBeaufort() }
  }

  private var temperatureUnit: String {
    detailModel.response?.dailyUnits["temperature_2m_min"] ?? "°C"
  }

  private var windSpeedUnit: String {
    if windSpeedSetting.usesBeaufortDisplay {
      return windSpeedSetting.displayUnit
    }
    return detailModel.response?.dailyUnits["wind_speed_10m_min"] ?? "km/h"
  }

  private var precipitationUnit: String {
    detailModel.response?.dailyUnits["precipitation_sum"] ?? "mm"
  }

  private var currentCoordinate: CLLocationCoordinate2D {
    location.coordinates
  }

  private var modelContextText: String {
    let model = detailModel.selectedModel

    switch model {
    case .ecmwfAIFS025Ensemble:
      return String(localized: "AIFS eignet sich gut für mittelfristige Unsicherheit, lokale Details können geglättet wirken.")
    case .ecmwfIFS025Ensemble:
      return String(localized: "IFS ENS liefert eine breit gestreute Unsicherheit für die mittlere Frist.")
    case .googleWeatherNext2Ensemble:
      return String(localized: "WeatherNext 2 ist ein KI-Modell und gut für mittelfristige Trends geeignet.")
    case .ncepAIGFS025:
      return String(localized: "AI GEFS ist ein guter Kompromiss für die nächsten ein bis zwei Wochen.")
    case .ncepGEFS05:
      return String(localized: "GEFS zeigt lange Trends, ist aber wegen des groben Gitters weniger lokal.")
    case .iconGlobalEPS:
      return String(localized: "ICON Global EPS passt für kurze bis mittlere Trends weltweit.")
    case .iconEUEPS:
      return String(localized: "ICON EU EPS ist für Europa feiner aufgelöst, reicht aber nur wenige Tage.")
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        DailyDetailSegmentedControl(selectedSection: $selectedSection)

        TabView(selection: $selectedSection) {
          ForEach(DailyDetailSection.allCases) { section in
            sectionPage(for: section)
              .tag(section)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.container, edges: .bottom)
      }
      .navigationTitle("Ensemble \(detailModel.selectedModel.displayName)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          modelMenu
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: "Fertig"), action: finish)
        }
      }
      .sensoryFeedback(.success, trigger: dismissalFeedback)
      .task(id: detailModel.selectedModel) {
        await detailModel.load(coordinates: currentCoordinate, force: true)
      }
    }
  }

  @ViewBuilder
  private func sectionPage(for section: DailyDetailSection) -> some View {
    ScrollView {
      if points.isEmpty && !detailModel.isLoading {
        ContentUnavailableView(
          "Keine Ensemble-Daten",
          systemImage: "chart.line.downtrend.xyaxis",
          description: detailModel.errorMessage != nil
            ? Text(detailModel.errorMessage!)
            : Text("Außerhalb der Modellabdeckung")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
      } else {
        LazyVStack(alignment: .leading, spacing: 16) {
          switch section {
          case .temperature:
            temperatureSection
            if !points.isEmpty {
              DailyEnsembleTemperatureSummaryCard(points: points, unit: temperatureUnit)
            }
          case .precipitation:
            precipitationSumSection
            if !points.isEmpty {
              DailyEnsemblePrecipitationSummaryCard(points: points, unit: precipitationUnit)
            }
          case .wind:
            windSection
            if !points.isEmpty {
              DailyEnsembleWindSummaryCard(points: windPoints, unit: windSpeedUnit)
            }
          }
          ensembleContextCard
          if section == .wind && windSpeedSetting.usesBeaufortDisplay {
            BeaufortScaleInfoCard()
          }
        }
        .padding()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea(.container, edges: .bottom)
  }

  private var modelMenu: some View {
    Menu {
      ForEach(DailyEnsembleModel.modelsByProvider, id: \.provider.rawValue) { group in
        Section(group.provider.rawValue) {
          ForEach(group.models) { model in
            Button {
              detailModel.selectedModel = model
            } label: {
              if detailModel.selectedModel == model {
                Label("\(model.displayName) · \(model.menuSubtitle)", systemImage: "checkmark")
              } else {
                Text("\(model.displayName) · \(model.menuSubtitle)")
              }
            }
          }
        }
      }
    } label: {
      Label(detailModel.selectedModel.displayName, systemImage: "slider.horizontal.3")
        .labelStyle(.iconOnly)
    }
    .accessibilityLabel(Text("Wettermodell"))
  }

  private var temperatureSection: some View {
    DailyDetailChartCard(
      title: "Temperatur",
      color: .red,
      isLoading: detailModel.isLoading && points.isEmpty
    ) {
      if points.isEmpty {
        DailyDetailLoadingChart()
      } else {
        DailyEnsembleTemperatureChart(
          points: points,
          unit: temperatureUnit
        )
      }
    }
  }

  private var windSection: some View {
    DailyDetailChartCard(
      title: "Wind",
      color: .cyan,
      isLoading: detailModel.isLoading && points.isEmpty
    ) {
      if points.isEmpty {
        DailyDetailLoadingChart()
      } else {
        DailyEnsembleWindChart(
          points: windPoints,
          unit: windSpeedUnit
        )
      }
    }
  }

  private var precipitationSumSection: some View {
    DailyDetailChartCard(
      title: "Niederschlagssumme",
      color: .blue,
      isLoading: detailModel.isLoading && points.isEmpty
    ) {
      if points.isEmpty {
        DailyDetailLoadingChart()
      } else {
        DailyEnsemblePrecipitationSumChart(
          points: points,
          unit: precipitationUnit
        )
      }
    }
  }

  private var ensembleContextCard: some View {
    EnvironmentDetailCard {
      Text("Ensemble-Vorhersage")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Text("Unsicherheit & Modell")
        .font(.headline.weight(.semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)

      Text(
        String(
          format: String(localized: "Mehrere Modellläufe zeigen, wie stabil die Vorhersage ist. %@"),
          modelContextText
        )
      )
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        detailPill("\(points.count) Tage", color: .blue)
        detailPill("\(detailModel.selectedModel.members) Mitglieder", color: .teal)
        detailPill(detailModel.selectedModel.region, color: .green)
      }
      .padding(.top, 2)
    }
  }

  private func detailPill(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.18), in: .capsule)
      .foregroundStyle(color)
  }

  private func finish() {
    dismissalFeedback.toggle()
    dismiss()
  }
}

extension DailyDetailView {
  @MainActor
  @Observable
  final class DetailModel {
    var selectedModel: DailyEnsembleModel = .iconGlobalEPS
    var response: DailyEnsembleForecastResponse?
    var isLoading = false
    var errorMessage: String?

    private let client = APIClient.shared
    private var loadedKeys: Set<String> = []

    func load(coordinates: CLLocationCoordinate2D, force: Bool = false) async {
      let outboundCoordinates = LocationService.outboundCoordinate(coordinates)
      let key = "\(outboundCoordinates.latitude),\(outboundCoordinates.longitude),\(selectedModel.rawValue)"
      guard force || !loadedKeys.contains(key) else { return }

      isLoading = true
      errorMessage = nil
      response = nil

      do {
        response = try await client.getDailyEnsembleForecast(
          coordinates: coordinates,
          model: selectedModel
        )
        loadedKeys.insert(key)
      } catch {
        errorMessage = error.localizedDescription
      }

      isLoading = false
    }
  }
}

private struct DailyDetailChartCard<Content: View>: View {
  let title: LocalizedStringKey
  let color: Color
  let isLoading: Bool
  private let content: Content

  init(
    title: LocalizedStringKey,
    color: Color,
    isLoading: Bool,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.color = color
    self.isLoading = isLoading
    self.content = content()
  }

  var body: some View {
    EnvironmentDetailCard {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ZStack {
        content
      }
    }
    .accessibilityElement(children: .contain)
  }
}

private struct DailyDetailLoadingChart: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.secondary.opacity(0.08))
      ProgressView()
    }
    .frame(height: 220)
  }
}

private extension DailyEnsembleDayPoint {
  func convertingWindSpeedsToBeaufort() -> DailyEnsembleDayPoint {
    DailyEnsembleDayPoint(
      id: id,
      date: date,
      temperatureMin: temperatureMin,
      temperatureMax: temperatureMax,
      temperatureMinMemberLow: temperatureMinMemberLow,
      temperatureMinMemberHigh: temperatureMinMemberHigh,
      temperatureMaxMemberLow: temperatureMaxMemberLow,
      temperatureMaxMemberHigh: temperatureMaxMemberHigh,
      precipitationSum: precipitationSum,
      precipitationSumMemberLow: precipitationSumMemberLow,
      precipitationSumMemberHigh: precipitationSumMemberHigh,
      windSpeedMin: BeaufortScale.value(forKilometersPerHour: windSpeedMin),
      windSpeedMax: BeaufortScale.value(forKilometersPerHour: windSpeedMax),
      windSpeedMinMemberLow: BeaufortScale.value(forKilometersPerHour: windSpeedMinMemberLow),
      windSpeedMinMemberHigh: BeaufortScale.value(forKilometersPerHour: windSpeedMinMemberHigh),
      windSpeedMaxMemberLow: BeaufortScale.value(forKilometersPerHour: windSpeedMaxMemberLow),
      windSpeedMaxMemberHigh: BeaufortScale.value(forKilometersPerHour: windSpeedMaxMemberHigh),
      windDirection: windDirection,
      windDirectionMemberLow: windDirectionMemberLow,
      windDirectionMemberHigh: windDirectionMemberHigh
    )
  }
}
