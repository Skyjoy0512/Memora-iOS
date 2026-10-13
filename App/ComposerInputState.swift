import SwiftUI
import UIKit

@MainActor
@Observable
final class ComposerInputState {
  var value: Snapshot?
  @ObservationIgnored weak var inputView: UIView?

  struct Snapshot: Equatable {
    var text: String
    var selection: NSRange
    var hasMarkedText: Bool
  }

  func snapshot() -> Snapshot? {
    guard let view = inputView, view.isFirstResponder,
          (view as? UITextField)?.isSecureTextEntry != true, (view as? UITextView)?.isSecureTextEntry != true,
          let input = view as? any UITextInput,
          let selected = input.selectedTextRange,
          let document = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument),
          let text = input.text(in: document) else { return nil }
    return Snapshot(text: text, selection: NSRange(location: input.offset(from: input.beginningOfDocument, to: selected.start), length: input.offset(from: selected.start, to: selected.end)), hasMarkedText: input.markedTextRange != nil)
  }
}
