import SwiftUI

/// A saved place in the Orte list: live-conditions card with the edit,
/// default and delete actions in the context menu and as swipe actions.
struct LocationCityRow: View {
    let personalization: PlacePersonalization
    let isDefault: Bool
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleDefault: () -> Void

    var body: some View {
        Button(action: onSelect) {
            CityCard(
                personalization: personalization,
                isDefault: isDefault,
                conditions: conditions,
                isSelected: isSelected,
                backdropPaused: backdropPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .placeRowActions(isDefault: isDefault, onEdit: onEdit, onToggleDefault: onToggleDefault, onDelete: onDelete)
        .listRowStyling()
    }
}
