import SwiftUI

// MARK: - Row cards

/// City row content as its own view, observing the managed object directly:
/// List rows diff by ForEach element, and an edited City is the SAME reference
/// as before — without the subscription a label/emoji edit never re-renders
/// the row until the sheet is reopened.
struct CityCard: View {
    @ObservedObject var city: City
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool

    var body: some View {
        let personalization = city.personalization
        LocationCard(
            title: personalization.title,
            detail: personalization.detailLine(condition: conditions?.conditionText),
            mark: personalization.mark,
            temperature: conditions?.temperature,
            snapshot: conditions?.snapshot,
            isSelected: isSelected,
            isDefault: city.isDefault,
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
    private var cityService = CityService.shared

    init(conditions: CityConditions?, isSelected: Bool, backdropPaused: Bool) {
        self.conditions = conditions
        self.isSelected = isSelected
        self.backdropPaused = backdropPaused
    }

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
}
