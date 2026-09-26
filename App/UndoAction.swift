import Foundation

/// One recent deletion that can still be taken back. `undo` puts the record
/// back; `finalize` runs when the offer is passed over or replaced, and is where
/// a delayed file removal actually happens.
struct UndoAction {
  var id = UUID()
  var message: String
  var undo: () -> Void
  var finalize: () -> Void
}
