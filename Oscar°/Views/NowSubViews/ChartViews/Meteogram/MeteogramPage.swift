import SwiftUI

/// The "Meteogramm" page of the hourly detail sheet: readout header, the
/// stacked panel meteogram, and the full-range overview minimap.
///
/// The model is built in init rather than onAppear: with a nil model the body
/// would be empty, and onAppear never fires on empty content. Panel scrolling
/// is ganged by a page-local `ChartScrollSynchronizer`; the minimap drives and
/// tracks it via normalized offsets, never through per-frame SwiftUI state.
struct MeteogramPage: View {
  private let model: MeteogramModel?

  @State private var synchronizer = ChartScrollSynchronizer()
  @State private var zoom: MeteogramZoom
  @State private var scrollAnchor: Date
  @State private var normalizedOffset: CGFloat
  @State private var rawSelection: Date?
  @State private var selectedIndex: Int?

  init(input: MeteogramModel.Input, initialScrollPosition: Date) {
    let model = MeteogramModel(input: input)
    self.model = model

    var zoom = MeteogramZoom.hours36
    if let model, !model.availableZooms.contains(zoom) {
      zoom = model.availableZooms[0]
    }
    _zoom = State(initialValue: zoom)

    var anchor = initialScrollPosition
    var offset: CGFloat = 0
    if let model {
      anchor = Self.clampedAnchor(initialScrollPosition, model: model, zoom: zoom)
      offset = Self.normalizedOffset(forAnchor: anchor, model: model, zoom: zoom)
    }
    _scrollAnchor = State(initialValue: anchor)
    _normalizedOffset = State(initialValue: offset)
  }

  var body: some View {
    if let model {
      VStack(spacing: 16) {
        EnvironmentDetailCard {
          Text("Meteogramm")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          MeteogramChart(
            model: model,
            zoom: zoom,
            selectedIndex: selectedIndex,
            synchronizer: synchronizer,
            initialScrollDate: scrollAnchor,
            rawSelection: $rawSelection
          )
          // Zoom changes rebuild the panels so the new visible domain and
          // initial position apply atomically to the whole synced group.
          .id(zoom)

          MeteogramLegend()

          MeteogramMinimap(
            model: model,
            normalizedOffset: normalizedOffset,
            visibleSeconds: effectiveVisibleSeconds(for: model),
            onScrub: scrub(toNormalizedOffset:)
          )
        }

        HourlyDetailInfoCard(
          title: "Einordnung",
          message:
            "Die weißen Bänder zeigen die Bewölkung in drei Höhenlagen, je dicker das Band, desto bedeckter der Himmel. Gelbe Flächen stehen für sonnige Abschnitte, Balken für Niederschlag, gestrichelte Verläufe für die Vergangenheit. Halte und ziehe für die Werte einer Stunde, mit zwei Fingern änderst du den Zeitraum."
        )
      }
      .onAppear {
        synchronizer.onNormalizedOffsetChange = { offset in
          normalizedOffset = offset
        }
      }
      .onChange(of: rawSelection) { _, selection in
        guard let selection else {
          selectedIndex = nil
          return
        }
        let snapped = model.snappedIndex(for: selection)
        if snapped != selectedIndex {
          selectedIndex = snapped
          UIApplication.shared.playHapticFeedback()
        }
      }
      .sensoryFeedback(.selection, trigger: zoom)
      .simultaneousGesture(magnifyGesture)
      .accessibilityLabel(Text(verbatim: accessibilityLabel(for: model)))
    }
  }

  // MARK: - Scrolling

  private func scrub(toNormalizedOffset offset: CGFloat) {
    synchronizer.scroll(toNormalizedOffset: offset)
  }

  private func effectiveVisibleSeconds(for model: MeteogramModel) -> TimeInterval {
    min(zoom.seconds, model.domainSeconds)
  }

  private static func clampedAnchor(_ date: Date, model: MeteogramModel, zoom: MeteogramZoom)
    -> Date
  {
    let latestStart = model.fullRange.upperBound.addingTimeInterval(
      -min(zoom.seconds, model.domainSeconds))
    let upper = max(model.fullRange.lowerBound, latestStart)
    return min(max(date, model.fullRange.lowerBound), upper)
  }

  private static func normalizedOffset(
    forAnchor anchor: Date, model: MeteogramModel, zoom: MeteogramZoom
  ) -> CGFloat {
    let domain = model.domainSeconds
    let window = min(zoom.seconds, domain)
    guard domain > window else { return 0 }
    return CGFloat(anchor.timeIntervalSince(model.fullRange.lowerBound) / (domain - window))
  }

  // MARK: - Zoom (pinch only)

  private func stepZoom(by delta: Int, in model: MeteogramModel) {
    let zooms = model.availableZooms
    let currentIndex = zooms.firstIndex(of: zoom) ?? 0
    let target = min(max(currentIndex + delta, 0), zooms.count - 1)
    let newZoom = zooms[target]
    guard newZoom != zoom else { return }

    // Keep the visual center anchored across the window change.
    let domain = model.domainSeconds
    let oldWindow = min(zoom.seconds, domain)
    let start = model.fullRange.lowerBound.addingTimeInterval(
      Double(normalizedOffset) * max(domain - oldWindow, 0))
    let center = start.addingTimeInterval(oldWindow / 2)
    let newAnchor = Self.clampedAnchor(
      center.addingTimeInterval(-newZoom.seconds / 2), model: model, zoom: newZoom)

    synchronizer.reset()
    scrollAnchor = newAnchor
    normalizedOffset = Self.normalizedOffset(forAnchor: newAnchor, model: model, zoom: newZoom)
    zoom = newZoom
    rawSelection = nil
    selectedIndex = nil
  }

  private var magnifyGesture: some Gesture {
    MagnifyGesture()
      .onEnded { value in
        guard let model else { return }
        let magnification = value.magnification
        // Map the pinch to discrete steps only when it ends — live domain
        // writes would rebuild the charts every frame and fight their pan.
        let delta: Int
        switch magnification {
        case ..<0.45: delta = 2
        case ..<0.77: delta = 1
        case 2.2...: delta = -2
        case 1.3...: delta = -1
        default: return
        }
        stepZoom(by: delta, in: model)
      }
  }

  private func accessibilityLabel(for model: MeteogramModel) -> String {
    String(localized: "Meteogramm") + ", "
      + "\(Int(model.temperatureMin.rounded()))° – \(Int(model.temperatureMax.rounded()))°"
  }

}
