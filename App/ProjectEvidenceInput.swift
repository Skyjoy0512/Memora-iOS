import Foundation

struct ProjectEvidenceInput: Codable, Equatable, Sendable {
  var target: ProjectCitation.Target
  var title: String
  var blocks: [ProjectSourceText]
}
