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
        .contextMenu {
            Button(action: onEdit) {
                Label("Bearbeiten", systemImage: "pencil")
            }
            defaultButton
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
            // The destructive role only reds the text — the icon follows the
            // cascading label tint and stayed white without this.
            .tint(.red)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Löschen", systemImage: "trash")
            }
            // Explicit red: the role's default is lost to the tab bar's
            // cascading white tint, same reason the neighbors set theirs.
            .tint(.red)
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
