import Foundation

/// One recent deletion that can still be taken back. `undo` puts the record
/// back; `finalize` runs when the offer is passed over or replaced, and is where
/// a delayed file removal actually happens.
struct UndoAction {
  var id = UUID()
  var message: String
  var undo: () -> Bool
  var finalize: () -> Void

  init(message: String, undo: @escaping () -> Void, finalize: @escaping () -> Void) {
    self.message = message
    self.undo = { undo(); return true }
    self.finalize = finalize
  }

  static func retryable(message: String, attempt: @escaping () -> Bool, finalize: @escaping () -> Void) -> Self {
    var action = Self(message: message, undo: {}, finalize: finalize)
    action.undo = attempt
    return action
  }
}
