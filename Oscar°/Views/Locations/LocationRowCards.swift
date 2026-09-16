import SwiftUI

// MARK: - Row cards

/// City row content. Personalization and the default flag arrive as values:
/// an edited City is the SAME reference as before, so a row keyed on the
/// object alone would never re-render, while every mutation goes through
/// CityService.save(), which reassigns `cities` and re-runs the list body.
struct CityCard: View {
    let personalization: PlacePersonalization
    let isDefault: Bool
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool

    var body: some View {
        LocationCard(
            title: personalization.title,
            detail: personalization.detailLine(condition: conditions?.conditionText),
            mark: personalization.mark,
            temperature: conditions?.temperature,
            snapshot: conditions?.snapshot,
            isSelected: isSelected,
            isDefault: isDefault,
            backdropPaused: backdropPaused
        )
    }
}

/// The GPS pseudo-entry's card: personalization and the default flag come from
/// CityService's observable UserDefaults mirror instead of a City entity —
/// read HERE in body (not passed in) so the lazy List row re-renders on its
/// own observation, independent of parent/row diffing.
struct CurrentLocationCard: View {
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool
    let cityService = CityService.shared

    var body: some View {
        let personalization = cityService.currentLocationPersonalization
        LocationCard(
            title: personalization.title,
            detail: personalization.detailLine(condition: conditions?.conditionText),
            mark: personalization.mark,
            temperature: conditions?.temperature,
            snapshot: conditions?.snapshot,
            isSelected: isSelected,
            isDefault: cityService.defaultIsCurrentLocation,
            backdropPaused: backdropPaused
        )
    }
}

extension View {
    /// Card rows manage their own background and spacing.
    func listRowStyling() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// Edit and default actions of an Orte row as context menu and swipe
    /// actions; saved places add delete (full swipe) in front of edit.
    func placeRowActions(
        isDefault: Bool,
        onEdit: @escaping () -> Void,
        onToggleDefault: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        let editButton = Button(action: onEdit) {
            Label("Bearbeiten", systemImage: "pencil")
        }
        let defaultButton = Button(action: onToggleDefault) {
            if isDefault {
                Label("Standard entfernen", systemImage: "star.slash")
            } else {
                Label("Als Standard festlegen", systemImage: "star")
            }
        }
        return self
            .contextMenu {
                editButton
                defaultButton
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                    // The destructive role only reds the text — the icon follows the
                    // cascading label tint and stayed white without this.
                    .tint(.red)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: onDelete != nil) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
                    // Explicit red: the role's default is lost to the tab bar's
                    // cascading white tint, same reason the neighbors set theirs.
                    .tint(.red)
                }
                editButton
                    .tint(.indigo)
            }
            .swipeActions(edge: .leading) {
                defaultButton
                    .tint(.yellow)
            }
    }
}
