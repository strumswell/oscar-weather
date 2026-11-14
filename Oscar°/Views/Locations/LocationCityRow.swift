import SwiftUI

struct LocationCityRow: View {
    let personalization: PlacePersonalization
    let isDefault: Bool
    let isNotificationPlace: Bool
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleDefault: () -> Void
    let onNotifyHere: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            CityCard(
                personalization: personalization,
                isDefault: isDefault,
                isNotificationPlace: isNotificationPlace,
                conditions: conditions,
                isSelected: isSelected,
                backdropPaused: backdropPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .placeRowActions(isDefault: isDefault, onEdit: onEdit, onToggleDefault: onToggleDefault, onNotifyHere: onNotifyHere, onDelete: onDelete)
        .listRowStyling()
    }
}
