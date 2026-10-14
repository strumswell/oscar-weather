import SwiftUI

// MARK: - Row cards

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
    func listRowStyling() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

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
                    .tint(.red)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: onDelete != nil) {
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("Löschen", systemImage: "trash")
                    }
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
