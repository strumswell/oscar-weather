//
//  LocationEditSheet.swift
//  Oscar°
//
//  Personalizes a place: an emoji, an own name ("Zuhause", "Oma"), and the
//  launch-default toggle. Works for saved cities and for the GPS
//  "current location" pseudo-entry, which is no City entity.
//

import SwiftUI

/// What the edit sheet operates on: a saved city, or the current location
/// (whose personalization lives in UserDefaults, see CityService).
enum LocationEditTarget: Identifiable {
    case city(City)
    case currentLocation

    var id: String {
        switch self {
        case .city(let city):
            city.objectID.uriRepresentation().absoluteString
        case .currentLocation:
            "current-location"
        }
    }
}

struct LocationEditSheet: View {
    let target: LocationEditTarget

    @Environment(\.dismiss) private var dismiss
    @State private var customLabel: String
    @State private var mark: PlacePersonalization.Mark
    @State private var isDefault: Bool
    @FocusState private var emojiFieldFocused: Bool
    private let cityService = CityService.shared

    /// Curated set covering the common cases (home, work, family, travel).
    private static let emojiChoices = [
        "🏠", "🏢", "💼", "🏫", "👵", "👴", "👨‍👩‍👧", "❤️",
        "🌲", "⛰️", "🏖️", "🌊", "🎿", "🏕️", "⚽️", "🚜",
        "✈️", "🚗", "⛵️", "🎡", "🐶", "🐴", "🍇", "🎣",
    ]

    /// Label suggestions; picking one also proposes a fitting emoji when
    /// none is chosen yet.
    private static let labelSuggestions: [(label: String, emoji: String)] = [
        (String(localized: "Zuhause"), "🏠"),
        (String(localized: "Arbeit"), "💼"),
        (String(localized: "Schule"), "🏫"),
        (String(localized: "Familie"), "❤️"),
        (String(localized: "Urlaub"), "🏖️"),
    ]

    init(target: LocationEditTarget) {
        self.target = target
        switch target {
        case .city(let city):
            _customLabel = State(initialValue: city.customLabel ?? "")
            _mark = State(initialValue: city.personalization.mark)
            _isDefault = State(initialValue: city.isDefault)
        case .currentLocation:
            let service = CityService.shared
            _customLabel = State(initialValue: service.currentLocationCustomLabel ?? "")
            _mark = State(initialValue: service.currentLocationPersonalization.mark)
            _isDefault = State(initialValue: service.defaultIsCurrentLocation)
        }
    }

    private var isCurrentLocationTarget: Bool {
        if case .currentLocation = target { return true }
        return false
    }

    /// What "nothing picked" means for this target: the GPS entry falls back
    /// to its location glyph, a saved city to no mark at all.
    private var standardMark: PlacePersonalization.Mark {
        isCurrentLocationTarget ? .locationGlyph : .plain
    }

    private var placeName: String {
        switch target {
        case .city(let city):
            city.label ?? ""
        case .currentLocation:
            String(localized: "Mein Standort")
        }
    }

    private var nameFooter: Text {
        switch target {
        case .city:
            Text("Der Ortsname bleibt als Untertitel sichtbar.")
        case .currentLocation:
            Text("„Mein Standort“ bleibt als Untertitel sichtbar.")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeName, text: $customLabel)
                        .submitLabel(.done)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Self.labelSuggestions, id: \.label) { suggestion in
                                Button {
                                    withAnimation(.snappy) {
                                        customLabel = suggestion.label
                                        // Only propose an emoji while the mark
                                        // is untouched — an explicit choice
                                        // (incl. "none") is respected.
                                        if mark == standardMark {
                                            mark = .emoji(suggestion.emoji)
                                        }
                                    }
                                    UIApplication.shared.playHapticFeedback()
                                } label: {
                                    Text("\(suggestion.emoji) \(suggestion.label)")
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.fill.tertiary, in: Capsule())
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .listRowSeparator(.hidden, edges: .bottom)
                } header: {
                    Text("Eigener Name")
                } footer: {
                    nameFooter
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        if isCurrentLocationTarget {
                            markCell(.locationGlyph, symbol: "location.fill")
                                .accessibilityLabel(Text("Standortsymbol"))
                        }
                        markCell(.plain, symbol: "circle.slash")
                            .accessibilityLabel(isCurrentLocationTarget ? Text("Kein Symbol") : Text("Kein Emoji"))
                        ForEach(Self.emojiChoices, id: \.self) { choice in
                            markCell(.emoji(choice))
                                .accessibilityLabel(Text(choice))
                        }
                        customEmojiCell
                    }
                    .padding(.vertical, 4)
                } header: {
                    isCurrentLocationTarget ? Text("Symbol") : Text("Emoji")
                }

                Section {
                    // Stock switch green; the tab's cascading label tint would
                    // paint the track white/black.
                    Toggle("Standardort", isOn: $isDefault)
                        .tint(.green)
                } footer: {
                    Text("Oscar° startet mit diesem Ort.")
                }
            }
            .navigationTitle(placeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        save()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// One selectable cell in the mark grid — shared chrome and selection;
    /// the face is the given SF symbol, or the mark's emoji itself.
    private func markCell(_ value: PlacePersonalization.Mark, symbol: String? = nil) -> some View {
        let isSelected = mark == value
        return Button {
            withAnimation(.snappy) { mark = value }
            UIApplication.shared.playHapticFeedback()
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
                } else {
                    Text(value.emoji ?? "")
                        .font(.system(size: 22))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(cellFill(isSelected: isSelected, isSymbol: symbol != nil))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.blue, lineWidth: isSelected ? 2 : 0)
            )
            .scaleEffect(isSelected && symbol == nil ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Symbol cells keep a filled base so the glyph reads as a button; emoji
    /// are their own face and sit on clear. Selection highlights either way.
    private func cellFill(isSelected: Bool, isSymbol: Bool) -> AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.fill.secondary) }
        return isSymbol ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear)
    }

    /// Whether the chosen emoji came from the keyboard rather than the grid.
    private var customEmojiSelected: Bool {
        guard let emoji = mark.emoji else { return false }
        return !Self.emojiChoices.contains(emoji)
    }

    /// Free choice beyond the curated grid: the cell opens the emoji keyboard
    /// and shows whatever was picked there.
    private var customEmojiCell: some View {
        ZStack {
            if customEmojiSelected, let emoji = mark.emoji {
                Text(emoji)
                    .font(.system(size: 22))
            } else {
                Image(systemName: "face.smiling")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                            .offset(x: 6, y: 4)
                    }
            }
            EmojiKeyboardField(isFocused: $emojiFieldFocused) { picked in
                withAnimation(.snappy) { mark = .emoji(picked) }
                UIApplication.shared.playHapticFeedback()
                emojiFieldFocused = false
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(customEmojiSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    emojiFieldFocused || customEmojiSelected ? .blue : .clear,
                    lineWidth: 2
                )
        )
        .contentShape(.rect)
        .onTapGesture {
            emojiFieldFocused = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Eigenes Emoji"))
        .accessibilityAddTraits(customEmojiSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func save() {
        switch target {
        case .city(let city):
            cityService.updateCity(city, emoji: mark.emoji, customLabel: customLabel)
            if isDefault != city.isDefault {
                cityService.setDefault(city: isDefault ? city : nil)
            }
        case .currentLocation:
            cityService.updateCurrentLocation(mark: mark, customLabel: customLabel)
            if isDefault != cityService.defaultIsCurrentLocation {
                cityService.setDefault(city: nil, asCurrentLocation: isDefault)
            }
        }
        UIApplication.shared.playHapticFeedback()
        dismiss()
    }
}
