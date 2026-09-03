import CoreLocation
import Foundation

extension DailyDetailView {
  @MainActor
  @Observable
  final class DetailModel {
    var selectedModel: DailyEnsembleModel = .ecmwfIFS025Ensemble
    var response: DailyEnsembleForecastResponse?
    var isLoading = false
    var errorMessage: String?

    private let client = APIClient.shared
    private var loadGeneration = 0

    func load(coordinates: CLLocationCoordinate2D) async {
      loadGeneration += 1
      let generation = loadGeneration
      isLoading = true
      errorMessage = nil
      response = nil

      do {
        let loaded = try await client.getDailyEnsembleForecast(
          coordinates: coordinates,
          model: selectedModel
        )
        guard generation == loadGeneration else { return }
        response = loaded
      } catch is CancellationError {
        return
      } catch let error as URLError where error.code == .cancelled {
        return
      } catch {
        guard generation == loadGeneration else { return }
        errorMessage = error.localizedDescription
      }

      isLoading = false
    }
  }
}
