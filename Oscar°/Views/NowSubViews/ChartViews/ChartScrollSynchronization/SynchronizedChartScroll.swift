import Charts
import SwiftUI

extension View {
    func synchronizedChartScroll(
        initialX: Date,
        using synchronizer: ChartScrollSynchronizer
    ) -> some View {
        chartScrollPosition(initialX: initialX)
            .background {
                ChartScrollViewLocator(synchronizer: synchronizer)
                    .allowsHitTesting(false)
            }
    }
}
