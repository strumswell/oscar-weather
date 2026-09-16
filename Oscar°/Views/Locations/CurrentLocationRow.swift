import SwiftUI

/// The GPS place at the top of the Orte list; cannot be moved or deleted.
struct CurrentLocationRow: View {
    let conditions: CityConditions?
    let isSelected: Bool
    let isDefault: Bool
    let backdropPaused: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onToggleDefault: () -> Void

    var body: some View {
        Button(action: onSelect) {
            CurrentLocationCard(
                conditions: conditions,
                isSelected: isSelected,
                backdropPaused: backdropPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .placeRowActions(isDefault: isDefault, onEdit: onEdit, onToggleDefault: onToggleDefault)
        .listRowStyling()
        .moveDisabled(true)
        .deleteDisabled(true)
    }
}
