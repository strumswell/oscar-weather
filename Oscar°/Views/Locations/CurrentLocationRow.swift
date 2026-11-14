import SwiftUI

struct CurrentLocationRow: View {
    let conditions: CityConditions?
    let isSelected: Bool
    let isDefault: Bool
    let isNotificationPlace: Bool
    let backdropPaused: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onToggleDefault: () -> Void
    let onNotifyHere: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            CurrentLocationCard(
                conditions: conditions,
                isSelected: isSelected,
                isNotificationPlace: isNotificationPlace,
                backdropPaused: backdropPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .placeRowActions(isDefault: isDefault, onEdit: onEdit, onToggleDefault: onToggleDefault, onNotifyHere: onNotifyHere)
        .listRowStyling()
        .moveDisabled(true)
        .deleteDisabled(true)
    }
}
