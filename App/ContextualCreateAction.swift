import Foundation

/// The create action for the screen currently shown, drawn as a small round
/// button above the tab bar's "＋". Each screen offers at most one.
struct ContextualCreateAction: Identifiable {
  var id: String
  var title: String
  var symbol: String
  var action: () -> Void
}
