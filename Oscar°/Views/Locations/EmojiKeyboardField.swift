import SwiftUI

// MARK: - Emoji keyboard input

/// An invisible text field pinned to the emoji keyboard: any emoji typed is
/// reported and the field clears itself. Non-emoji input is ignored.
struct EmojiKeyboardField: UIViewRepresentable {
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
