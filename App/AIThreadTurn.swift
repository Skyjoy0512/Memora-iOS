import Foundation

/// One turn of the open Ask AI conversation as it is kept between launches:
/// only who said what, since sources and steps belong to the moment.
struct AIThreadTurn: Codable, Hashable {
  var isUser: Bool
  var text: String
  var date: Date
  /// Set when a resident agent posted the turn; older saved turns have none.
  var residentName: String?
  var residentSymbol: MemoraIcon?
}
