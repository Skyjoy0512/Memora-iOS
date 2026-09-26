import UIKit

/// A text view that asks for the emoji keyboard when it becomes active.
final class EmojiTextView: UITextView {
  override var textInputMode: UITextInputMode? {
    UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
  }
}
