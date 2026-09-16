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
    WindSpeedUnit(settingValue: settingsService.windSpeedUnit)
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

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        DetailSectionPicker(label: "Ensemble-Details", selection: $selectedSection)

        TabView(selection: $selectedSection) {
          ForEach(DailyDetailSection.allCases) { section in
            DailyDetailSectionPage(
              section: section,
              points: points,
              windPoints: windPoints,
              temperatureUnit: temperatureUnit,
              windSpeedUnit: windSpeedUnit,
              precipitationUnit: precipitationUnit,
              usesBeaufortDisplay: windSpeedSetting.usesBeaufortDisplay,
              isLoading: detailModel.isLoading,
              errorMessage: detailModel.errorMessage,
              selectedModel: detailModel.selectedModel
            )
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
          Button(role: .close, action: finish)
        }
      }
      .sensoryFeedback(.success, trigger: dismissalFeedback)
      .task(id: detailModel.selectedModel) {
        await detailModel.load(coordinates: currentCoordinate)
      }
    }
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

  private func finish() {
    dismissalFeedback.toggle()
    dismiss()
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
