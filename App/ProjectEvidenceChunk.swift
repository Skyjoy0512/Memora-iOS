import Foundation

struct ProjectEvidenceChunk: Hashable, Codable, Sendable {
  var projectID: UUID
  var target: ProjectCitation.Target
  var title: String
  var text: String
  var page: Int?
  var time: TimeInterval?
}
