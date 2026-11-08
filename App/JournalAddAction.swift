import Foundation

/// One choice in a journal insertion menu. The handler already knows the
/// timeline position it was opened from.
struct JournalAddAction: Identifiable {
  var id: String { title }
  var title: String
  var icon: MemoraIcon
  var handler: () -> Void
}
