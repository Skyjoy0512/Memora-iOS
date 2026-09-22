import Foundation

/// The content of one shared item: a project with its records, or a single
/// record with its tasks. It is encoded to JSON and carried in one CloudKit
/// field, so sharing does not need a CloudKit field for every property.
struct TeamShareSnapshot: Codable {
  enum Kind: String, Codable {
    case project
    case meeting
  }

  var kind: Kind
  /// The project, when a whole project is shared.
  var space: MemoraSpace?
  var meetings: [Meeting]
  var tasks: [MemoraTask]
}
