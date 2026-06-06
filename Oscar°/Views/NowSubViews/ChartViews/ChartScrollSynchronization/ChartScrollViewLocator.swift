import SwiftUI

@MainActor
struct ChartScrollViewLocator: UIViewRepresentable {
    let synchronizer: ChartScrollSynchronizer

    func makeUIView(context: Context) -> LocatorView {
        LocatorView(synchronizer: synchronizer)
    }

    func updateUIView(_ uiView: LocatorView, context: Context) {
        uiView.updateSynchronizer(synchronizer)
        uiView.locateScrollView()
    }

    static func dismantleUIView(_ uiView: LocatorView, coordinator: Void) {
        uiView.detach()
    }

    @MainActor
    final class LocatorView: UIView {
        private var synchronizer: ChartScrollSynchronizer
        private weak var locatedScrollView: UIScrollView?
        private var lookupTask: Task<Void, Never>?
        private var remainingLookupAttempts = 8

        init(synchronizer: ChartScrollSynchronizer) {
            self.synchronizer = synchronizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            locateScrollView()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            locateScrollView()
        }

        func updateSynchronizer(_ newSynchronizer: ChartScrollSynchronizer) {
            guard synchronizer !== newSynchronizer else { return }
            detach()
            synchronizer = newSynchronizer
        }

        func locateScrollView() {
            guard window != nil else { return }

            if let locatedScrollView {
                guard locatedScrollView.window === window,
                      locatedScrollView.superview != nil
                else {
                    synchronizer.unregister(locatedScrollView)
                    self.locatedScrollView = nil
                    scheduleLookup()
                    return
                }

                // Content size can be transiently zero during TabView layout.
                // Keep the known chart registered until it actually leaves.
                return
            }

            guard let scrollView = findChartScrollView() else {
                scheduleLookup()
                return
            }

            lookupTask?.cancel()
            lookupTask = nil
            remainingLookupAttempts = 8
            locatedScrollView = scrollView
            synchronizer.register(scrollView)
        }

        func detach() {
            lookupTask?.cancel()
            lookupTask = nil

            guard let locatedScrollView else { return }
            synchronizer.unregister(locatedScrollView)
            self.locatedScrollView = nil
        }

        private func scheduleLookup() {
            guard lookupTask == nil, remainingLookupAttempts > 0 else { return }

            remainingLookupAttempts -= 1
            lookupTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }

                lookupTask = nil
                if locatedScrollView == nil {
                    locateScrollView()
                }
            }
        }

        // Swift Charts does not expose its scroll view, so inspect each new
        // sibling subtree while walking up from the locator.
        private func findChartScrollView() -> UIScrollView? {
            guard let window else { return nil }

            let locatorFrame = convert(bounds, to: window)
            var previousBranch: UIView = self
            var ancestor = superview

            for _ in 0..<8 {
                guard let currentAncestor = ancestor else { break }

                var candidates: [UIScrollView] = []
                if let scrollView = currentAncestor as? UIScrollView {
                    candidates.append(scrollView)
                }
                for sibling in currentAncestor.subviews where sibling !== previousBranch {
                    candidates.append(contentsOf: scrollViews(in: sibling))
                }

                let usableCandidates = candidates.filter {
                    isUsableChartScrollView($0, locatorFrame: locatorFrame, in: window)
                }
                if let bestMatch = usableCandidates.min(by: {
                    matchScore(for: $0, locatorFrame: locatorFrame, in: window)
                        < matchScore(for: $1, locatorFrame: locatorFrame, in: window)
                }) {
                    return bestMatch
                }

                previousBranch = currentAncestor
                ancestor = currentAncestor.superview
            }

            return nil
        }

        private func scrollViews(in rootView: UIView) -> [UIScrollView] {
            var result: [UIScrollView] = []

            if let scrollView = rootView as? UIScrollView {
                result.append(scrollView)
            }
            for subview in rootView.subviews where subview !== self {
                result.append(contentsOf: scrollViews(in: subview))
            }

            return result
        }

        private func isUsableChartScrollView(
            _ scrollView: UIScrollView,
            locatorFrame: CGRect,
            in window: UIWindow
        ) -> Bool {
            guard scrollView.isScrollEnabled,
                  scrollView.bounds.width > 0,
                  scrollView.contentSize.width > scrollView.bounds.width + 1
            else {
                return false
            }

            let scrollFrame = scrollView.convert(scrollView.bounds, to: window)
            let intersection = locatorFrame.intersection(scrollFrame)
            guard !intersection.isNull else { return false }

            let minimumOverlap = min(locatorFrame.height, scrollFrame.height) * 0.5
            return intersection.height >= minimumOverlap
                && scrollFrame.height <= locatorFrame.height * 1.5
        }

        private func matchScore(
            for scrollView: UIScrollView,
            locatorFrame: CGRect,
            in window: UIWindow
        ) -> CGFloat {
            let scrollFrame = scrollView.convert(scrollView.bounds, to: window)
            return abs(scrollFrame.midY - locatorFrame.midY)
                + abs(scrollFrame.height - locatorFrame.height) * 0.5
        }
    }
}
