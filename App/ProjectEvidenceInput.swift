import Foundation

struct ProjectEvidenceInput: Codable, Sendable {
  var target: ProjectCitation.Target
  var title: String
  var blocks: [ProjectSourceText]
}
