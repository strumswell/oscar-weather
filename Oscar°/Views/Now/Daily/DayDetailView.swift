import SwiftUI

/// The open day in the wide 12-day list: the hourly chart for just that day
/// and a lens picker showing each lens' value at the playhead. Drag sideways
/// across the chart to scrub, tap to jump; vertical drags keep scrolling the
/// feed.
struct DayDetailView: View {
    let day: ClosedRange<Double>
    /// Where the playhead starts: now for today, noon for later days.
    let startTime: Double

    @Environment(Weather.self) private var weather
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var model = HourlyTimelineModel()
    @State private var lens = HourlyLens.overview

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            DayChart(model: model, lens: lens)
                .frame(height: 200)

            LensPicker(model: model, selection: $lens)

            Button {
                presentation.present(.hourly(Date(timeIntervalSince1970: model.scrubTime)))
            } label: {
                HStack(spacing: 2) {
                    Text("Stündlich")
                    Image(systemName: "chevron.forward")
                        .imageScale(.small)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
        }
        .onChange(of: day, initial: true) { load() }
        .onChange(of: weather.lastUpdated) { load() }
    }

    private func load() {
        model.update(from: weather)
        model.show(day: day, at: startTime)
    }
}

/// The hourly strip pinned to the day, with a scrub that leaves vertical
/// drags to the feed (the strip's own drag would swallow them).
private struct DayChart: View {
    let model: HourlyTimelineModel
    let lens: HourlyLens

    @State private var width: CGFloat = 1

    var body: some View {
        HourlyTimelineStrip(model: model, lens: lens)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = max($0, 1) }
            .gesture(HorizontalPan { x in model.scrub(to: time(at: x)) })
            .onTapGesture { location in model.glide(to: time(at: location.x)) }
    }

    private func time(at x: CGFloat) -> Double {
        let fraction = Double(min(max(x / width, 0), 1))
        return model.windowStart + fraction * model.windowSeconds
    }
}

/// A pan that only begins when the drag starts sideways, so the enclosing
/// ScrollView keeps every vertical drag.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        onChange(context.converter.localLocation.x)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}

/// Every lens as a tile with its value at the playhead; the selected one
/// drives the chart. Four across when they fit, else two.
private struct LensPicker: View {
    let model: HourlyTimelineModel
    @Binding var selection: HourlyLens

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(columns: 4)
            grid(columns: 2)
        }
    }

    private func grid(columns: Int) -> some View {
        let lenses = HourlyLens.allCases
        let rows = stride(from: 0, to: lenses.count, by: columns).map {
            Array(lenses[$0 ..< min($0 + columns, lenses.count)])
        }
        return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(rows, id: \.first) { row in
                GridRow {
                    ForEach(row) { lens in
                        LensTile(model: model, lens: lens, isSelected: lens == selection) {
                            withAnimation(.snappy) { selection = lens }
                        }
                    }
                }
            }
        }
    }
}

private struct LensTile: View {
    let model: HourlyTimelineModel
    let lens: HourlyLens
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: lens.systemImage)
                        .foregroundStyle(model.layout(for: lens).primaryColor)
                    Text(lens.title)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .font(.caption.weight(.medium))

                Text(verbatim: model.rowValue(for: lens) ?? "--")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(isSelected ? 0.14 : 0.05), in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
