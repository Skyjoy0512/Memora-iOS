import Foundation

/// A mail read from Gmail: who, what, when, and the text. `body` is empty when
/// only the summary was fetched.
struct GmailMessage: Identifiable, Hashable {
  var id: String
  var from: String
  var to: String
  var subject: String
  var date: Date?
  var snippet: String
  var body: String
}
