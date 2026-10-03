import Foundation

/// A word found in the person's mail that may belong in the glossary.
struct GlossaryCandidate: Identifiable, Hashable {
  enum Kind: String {
    case person = "人"
    case company = "会社"
    case term = "用語"
  }

  var term: String
  var kind: Kind
  /// How many mails it appeared in.
  var count: Int

  var id: String { term }
}
