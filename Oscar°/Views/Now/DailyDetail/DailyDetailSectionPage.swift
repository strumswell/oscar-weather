import SwiftUI

/// One page of the ensemble detail pager: the chart card for the selected
/// section, its summary card, and the model context footer. Own view so a
/// response change re-evaluates the pages, not the navigation chrome.
struct DailyDetailSectionPage: View {
  let section: DailyDetailSection
  let points: [DailyEnsembleDayPoint]
  let windPoints: [DailyEnsembleDayPoint]
  let temperatureUnit: String
  let windSpeedUnit: String
  let precipitationUnit: String
  let usesBeaufortDisplay: Bool
  let isLoading: Bool
  let errorMessage: String?
  let selectedModel: DailyEnsembleModel

  var body: some View {
    ScrollView {
      if points.isEmpty && !isLoading {
        ContentUnavailableView(
          "Keine Ensemble-Daten",
          systemImage: "chart.line.downtrend.xyaxis",
          description: errorMessage.map { Text($0) } ?? Text("Außerhalb der Modellabdeckung")
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
          if section == .wind && usesBeaufortDisplay {
            BeaufortScaleInfoCard()
          }
        }
        .padding()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea(.container, edges: .bottom)
  }

  private var temperatureSection: some View {
    DailyDetailChartCard(
      title: "Temperatur",
      color: .red,
      isLoading: isLoading && points.isEmpty
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
      isLoading: isLoading && points.isEmpty
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
      isLoading: isLoading && points.isEmpty
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
    DetailCard {
      Text("Ensemble-Vorhersage")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Text("Unsicherheit & Modell")
        .font(.headline.weight(.semibold))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)

      Text("Mehrere Modellläufe zeigen, wie stabil die Vorhersage ist. \(modelContextText)")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        detailPill("\(points.count) Tage", color: .blue)
        detailPill("\(selectedModel.members) Mitglieder", color: .teal)
        detailPill(LocalizedStringKey(selectedModel.region), color: .green)
      }
      .padding(.top, 2)
    }
  }

  private var modelContextText: String {
    switch selectedModel {
    case .ecmwfAIFS025Ensemble:
      String(localized: "AIFS eignet sich gut für mittelfristige Unsicherheit, lokale Details können geglättet wirken.")
    case .ecmwfIFS025Ensemble:
      String(localized: "IFS ENS liefert eine breit gestreute Unsicherheit für die mittlere Frist.")
    case .googleWeatherNext2Ensemble:
      String(localized: "WeatherNext 2 ist ein KI-Modell und gut für mittelfristige Trends geeignet.")
    case .ncepAIGFS025:
      String(localized: "AI GEFS ist ein guter Kompromiss für die nächsten ein bis zwei Wochen.")
    case .ncepGEFS05:
      String(localized: "GEFS zeigt lange Trends, ist aber wegen des groben Gitters weniger lokal.")
    case .iconGlobalEPS:
      String(localized: "ICON Global EPS passt für kurze bis mittlere Trends weltweit.")
    case .iconEUEPS:
      String(localized: "ICON EU EPS ist für Europa feiner aufgelöst, reicht aber nur wenige Tage.")
    }
  }

  private func detailPill(_ text: LocalizedStringKey, color: Color) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.18), in: .capsule)
      .foregroundStyle(color)
  }
}
