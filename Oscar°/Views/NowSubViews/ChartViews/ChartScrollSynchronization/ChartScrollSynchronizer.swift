import SwiftUI

/// Mirrors native Chart scroll offsets without invalidating SwiftUI on every display frame.
@MainActor
final class ChartScrollSynchronizer {
    @MainActor
    private final class Entry {
        weak var scrollView: UIScrollView?
        weak var panGestureRecognizer: UIPanGestureRecognizer?
        let panObserver: PanObserver

        init(scrollView: UIScrollView, panObserver: PanObserver) {
            self.scrollView = scrollView
            self.panGestureRecognizer = scrollView.panGestureRecognizer
            self.panObserver = panObserver
        }

        func detach() {
            panGestureRecognizer?.removeTarget(
                panObserver,
                action: #selector(PanObserver.handlePan(_:))
            )
        }
    }

    @MainActor
    private final class PanObserver {
        let action: (UIPanGestureRecognizer) -> Void

        init(action: @escaping (UIPanGestureRecognizer) -> Void) {
            self.action = action
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            action(gesture)
        }
    }

    @MainActor
    private final class DisplayLinkProxy {
        weak var target: ChartScrollSynchronizer?

        init(target: ChartScrollSynchronizer) {
            self.target = target
        }

        @objc func update(_ displayLink: CADisplayLink) {
            target?.updateSynchronizedOffsets()
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private weak var activeScrollView: UIScrollView?
    nonisolated(unsafe) private var displayLink: CADisplayLink?
    private var lastNormalizedOffset: CGFloat?
    private var lastNotifiedOffset: CGFloat?
    private var idleFrameCount = 0

    /// Invoked (throttled) with the current normalized offset whenever the
    /// synchronized group scrolls — lets an overview control track the
    /// viewport without observing UIKit itself.
    var onNormalizedOffsetChange: ((CGFloat) -> Void)?

    /// Programmatically scrolls every registered chart to the given
    /// normalized offset (0 = domain start, 1 = domain end minus viewport).
    func scroll(toNormalizedOffset offset: CGFloat) {
        let clamped = min(max(offset, 0), 1)
        lastNormalizedOffset = clamped
        for entry in entries.values {
            guard let scrollView = entry.scrollView else { continue }
            setNormalizedOffset(clamped, on: scrollView)
        }
        if lastNotifiedOffset != clamped {
            lastNotifiedOffset = clamped
            onNormalizedOffsetChange?(clamped)
        }
    }

    func register(_ scrollView: UIScrollView) {
        removeDeallocatedEntries()

        let identifier = ObjectIdentifier(scrollView)
        guard entries[identifier] == nil else { return }

        let panObserver = PanObserver { [weak self, weak scrollView] gesture in
            guard let self, let scrollView else { return }
            self.handlePan(gesture, in: scrollView)
        }
        scrollView.panGestureRecognizer.addTarget(
            panObserver,
            action: #selector(PanObserver.handlePan(_:))
        )
        entries[identifier] = Entry(scrollView: scrollView, panObserver: panObserver)

        if let lastNormalizedOffset {
            setNormalizedOffset(lastNormalizedOffset, on: scrollView)
        }
    }

    func unregister(_ scrollView: UIScrollView) {
        let identifier = ObjectIdentifier(scrollView)
        guard let entry = entries.removeValue(forKey: identifier) else { return }

        entry.detach()

        if activeScrollView === scrollView {
            activeScrollView = nil
            stopDisplayLink()
        }
    }

    func reset() {
        detachAllEntries()
        activeScrollView = nil
        lastNormalizedOffset = nil
        lastNotifiedOffset = nil
        idleFrameCount = 0
        stopDisplayLink()
    }

    deinit {
        displayLink?.invalidate()
        MainActor.assumeIsolated {
            entries.values.forEach { $0.detach() }
        }
    }

    private func handlePan(_ gesture: UIPanGestureRecognizer, in scrollView: UIScrollView) {
        switch gesture.state {
        case .began, .changed:
            activeScrollView = scrollView
            idleFrameCount = 0
            startDisplayLink(for: scrollView)
            synchronize(from: scrollView)
        case .ended:
            startDisplayLink(for: scrollView)
        case .cancelled, .failed:
            activeScrollView = nil
            stopDisplayLink()
        case .possible:
            break
        @unknown default:
            break
        }
    }

    private func startDisplayLink(for scrollView: UIScrollView) {
        guard displayLink == nil else { return }

        let proxy = DisplayLinkProxy(target: self)
        let displayLink = CADisplayLink(
            target: proxy,
            selector: #selector(DisplayLinkProxy.update(_:))
        )
        let maximumFramesPerSecond = Float(
            scrollView.window?.screen.maximumFramesPerSecond ?? 120
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(80, maximumFramesPerSecond),
            maximum: maximumFramesPerSecond,
            preferred: maximumFramesPerSecond
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateSynchronizedOffsets() {
        guard let activeScrollView else {
            stopDisplayLink()
            return
        }

        synchronize(from: activeScrollView)

        if activeScrollView.isTracking
            || activeScrollView.isDragging
            || activeScrollView.isDecelerating {
            idleFrameCount = 0
        } else {
            idleFrameCount += 1
            if idleFrameCount >= 4 {
                self.activeScrollView = nil
                stopDisplayLink()
            }
        }
    }

    private func synchronize(from source: UIScrollView) {
        guard let normalizedOffset = normalizedOffset(of: source) else { return }
        lastNormalizedOffset = normalizedOffset

        for entry in entries.values {
            guard let target = entry.scrollView, target !== source else { continue }
            setNormalizedOffset(normalizedOffset, on: target)
        }

        // Threshold keeps SwiftUI invalidations far below display rate.
        if abs((lastNotifiedOffset ?? -1) - normalizedOffset) > 0.002 {
            lastNotifiedOffset = normalizedOffset
            onNormalizedOffsetChange?(normalizedOffset)
        }
    }

    private func normalizedOffset(of scrollView: UIScrollView) -> CGFloat? {
        guard let range = horizontalScrollRange(of: scrollView) else { return nil }

        return min(
            max((scrollView.contentOffset.x - range.lowerBound) / range.distance, 0),
            1
        )
    }

    private func setNormalizedOffset(_ normalizedOffset: CGFloat, on scrollView: UIScrollView) {
        guard let range = horizontalScrollRange(of: scrollView) else { return }

        let targetX = range.lowerBound + normalizedOffset * range.distance
        guard abs(scrollView.contentOffset.x - targetX) > 0.25 else { return }
        scrollView.contentOffset.x = targetX
    }

    private func horizontalScrollRange(of scrollView: UIScrollView) -> ClosedRange<CGFloat>? {
        let lowerBound = -scrollView.adjustedContentInset.left
        let upperBound = max(
            lowerBound,
            scrollView.contentSize.width
                - scrollView.bounds.width
                + scrollView.adjustedContentInset.right
        )
        guard upperBound > lowerBound else { return nil }

        return lowerBound...upperBound
    }

    private func removeDeallocatedEntries() {
        let staleIdentifiers = entries.compactMap { identifier, entry in
            entry.scrollView == nil ? identifier : nil
        }
        for identifier in staleIdentifiers {
            entries.removeValue(forKey: identifier)?.detach()
        }
    }

    private func detachAllEntries() {
        entries.values.forEach { $0.detach() }
        entries.removeAll(keepingCapacity: true)
    }
}

private extension ClosedRange<CGFloat> {
    var distance: CGFloat {
        upperBound - lowerBound
    }
}
