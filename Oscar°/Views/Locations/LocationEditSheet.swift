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
    @State private var emoji: String?
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
            _emoji = State(initialValue: city.emoji)
            _isDefault = State(initialValue: city.isDefault)
        case .currentLocation:
            let service = CityService.shared
            _customLabel = State(initialValue: service.currentLocationCustomLabel ?? "")
            _emoji = State(initialValue: service.currentLocationEmoji)
            _isDefault = State(initialValue: service.defaultIsCurrentLocation)
        }
    }

    private var placeName: String {
        switch target {
        case .city(let city):
            city.label ?? ""
        case .currentLocation:
            String(localized: "Aktueller Standort")
        }
    }

    private var nameFooter: Text {
        switch target {
        case .city:
            Text("Der Ortsname bleibt als Untertitel sichtbar.")
        case .currentLocation:
            Text("„Aktueller Standort“ bleibt als Untertitel sichtbar.")
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
                                        if emoji == nil {
                                            emoji = suggestion.emoji
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

                Section("Emoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        noEmojiCell
                        ForEach(Self.emojiChoices, id: \.self) { choice in
                            emojiCell(choice)
                        }
                        customEmojiCell
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Standardort", isOn: $isDefault)
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

    private var noEmojiCell: some View {
        Button {
            withAnimation(.snappy) { emoji = nil }
        } label: {
            Image(systemName: "circle.slash")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.fill.tertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.blue, lineWidth: emoji == nil ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Kein Emoji"))
    }

    private func emojiCell(_ choice: String) -> some View {
        Button {
            withAnimation(.snappy) { emoji = choice }
            UIApplication.shared.playHapticFeedback()
        } label: {
            Text(choice)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(emoji == choice ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.blue, lineWidth: emoji == choice ? 2 : 0)
                )
                .scaleEffect(emoji == choice ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(choice))
        .accessibilityAddTraits(emoji == choice ? .isSelected : [])
    }

    /// Whether the chosen emoji came from the keyboard rather than the grid.
    private var customEmojiSelected: Bool {
        guard let emoji else { return false }
        return !Self.emojiChoices.contains(emoji)
    }

    /// Free choice beyond the curated grid: the cell opens the emoji keyboard
    /// and shows whatever was picked there.
    private var customEmojiCell: some View {
        ZStack {
            if customEmojiSelected, let emoji {
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
                withAnimation(.snappy) { emoji = picked }
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
            cityService.updateCity(city, emoji: emoji, customLabel: customLabel)
            if isDefault != city.isDefault {
                cityService.setDefault(city: isDefault ? city : nil)
            }
        case .currentLocation:
            cityService.updateCurrentLocation(emoji: emoji, customLabel: customLabel)
            if isDefault != cityService.defaultIsCurrentLocation {
                cityService.setDefault(city: nil, asCurrentLocation: isDefault)
            }
        }
        UIApplication.shared.playHapticFeedback()
        dismiss()
    }
}

// MARK: - Emoji keyboard input

/// An invisible text field pinned to the emoji keyboard: any emoji typed is
/// reported and the field clears itself. Non-emoji input is ignored.
private struct EmojiKeyboardField: UIViewRepresentable {
    var isFocused: FocusState<Bool>.Binding
    let onPick: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.tintColor = .clear
        field.textColor = .clear
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        if isFocused.wrappedValue, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused.wrappedValue, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiKeyboardField

        init(_ parent: EmojiKeyboardField) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if let picked = string.last(where: \.isEmoji) {
                parent.onPick(String(picked))
            }
            textField.text = ""
            return false
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused.wrappedValue = false
        }
    }
}

/// UITextField that opens with the system emoji keyboard.
final class EmojiTextField: UITextField {
    // A stable identifier keeps UIKit from restoring the last-used keyboard.
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" }
            ?? super.textInputMode
    }
}

private extension Character {
    /// True for anything the emoji keyboard produces (incl. flags and ZWJ
    /// sequences); digits/symbols that are merely emoji-capable don't count.
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
