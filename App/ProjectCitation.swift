import Foundation

/// A saved citation identifies retrieved evidence, rather than trusting IDs or
/// excerpts invented by the model. Targets are resolved again when opened.
struct ProjectCitation: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var target: Target
  var title: String
  var excerpt: String
  var page: Int?
  var time: TimeInterval?

  enum Target: Hashable, Codable, Sendable {
    case source(UUID)
    case meeting(UUID)
    case document(UUID)
  }
}
