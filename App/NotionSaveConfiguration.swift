import Foundation

/// An ephemeral snapshot, never persisted or included in tool results.
struct NotionSaveConfiguration: Equatable, Sendable {
  var token: String
  var parentPageID: String
}
