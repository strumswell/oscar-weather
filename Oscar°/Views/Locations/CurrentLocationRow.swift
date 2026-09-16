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
        .contextMenu {
            Button(action: onEdit) {
                Label("Bearbeiten", systemImage: "pencil")
            }
            defaultButton
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .leading) {
            defaultButton
                .tint(.yellow)
        }
        .listRowStyling()
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    private var defaultButton: some View {
        Button(action: onToggleDefault) {
            if isDefault {
                Label("Standard entfernen", systemImage: "star.slash")
            } else {
                Label("Als Standard festlegen", systemImage: "star")
            }
        }
    }
}
