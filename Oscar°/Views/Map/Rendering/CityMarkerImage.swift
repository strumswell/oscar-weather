import SwiftUI
import UIKit

@MainActor
enum CityMarkerImage {
    static func make() -> UIImage {
        let displaySize = CGSize(width: 34, height: 34 * 652 / 534)
        let tipY = displaySize.height * (635.0 / 652.0)
        let canvas = CGSize(width: displaySize.width, height: tipY * 2)
        let asset = UIImage(named: "SelectedCityMarker")
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            asset?.draw(in: CGRect(origin: .zero, size: displaySize))
        }
    }
}
