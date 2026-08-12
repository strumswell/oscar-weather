import SwiftUI
import UIKit

/// iOS-style marker replica (`SelectedCityMarker` asset, 534×652 with the
/// balloon tip at 97.4% height), shared by the weather map's selected-city
/// marker layer and the locations map picker's dropped pin. The canvas is twice
/// the tip's y so a CENTER-anchored image pins the tip on the coordinate.
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
