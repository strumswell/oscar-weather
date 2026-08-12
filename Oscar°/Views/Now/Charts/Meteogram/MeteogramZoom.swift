import Foundation

/// Discrete zoom steps for the meteogram's visible x-window (pinch-driven).
enum MeteogramZoom: Int, CaseIterable, Identifiable {
  case hours24
  case hours36
  case days3
  case days7
  case days14

  var id: Int { rawValue }

  var seconds: TimeInterval {
    switch self {
    case .hours24: 86_400
    case .hours36: 129_600
    case .days3: 259_200
    case .days7: 604_800
    case .days14: 1_209_600
    }
  }

  /// Stride for per-hour glyph marks (weather icons, wind arrows).
  var glyphStrideHours: Int {
    switch self {
    case .hours24, .hours36: 6
    case .days3: 12
    case .days7: 24
    case .days14: 48
    }
  }

  /// Hour stride for axis labels; nil renders a day-level grid without hour labels.
  var hourAxisStride: Int? {
    switch self {
    case .hours24: 3
    case .hours36: 6
    case .days3: 12
    case .days7, .days14: nil
    }
  }
}
