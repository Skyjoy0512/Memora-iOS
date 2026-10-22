import Foundation

struct ProjectSourceExtractionResult: Sendable {
  var blocks: [ProjectSourceText]
  var thumbnail: Data?
  var notice: String?
  var coverage = ProjectSource.TextCoverage.complete
}
