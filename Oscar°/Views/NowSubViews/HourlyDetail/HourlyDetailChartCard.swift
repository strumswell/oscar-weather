import SwiftUI

struct HourlyDetailChartCard<Content: View>: View {
    let title: LocalizedStringKey
    let value: String
    let badge: LocalizedStringKey?
    let color: Color
    let subtitle: LocalizedStringKey?
    private let content: Content

    init(
        title: LocalizedStringKey,
        value: String,
        badge: LocalizedStringKey? = nil,
        color: Color,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.badge = badge
        self.color = color
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        EnvironmentDetailCard {
            EnvironmentDetailHeaderView(
                title: title,
                value: value,
                badge: badge,
                color: color,
                subtitle: subtitle
            )

            content
        }
        .accessibilityElement(children: .contain)
    }
}
