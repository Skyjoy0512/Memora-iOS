import Foundation

struct ProjectSourceExtractionResult: Sendable {
  var blocks: [ProjectSourceText]
  var thumbnail: Data?
  var notice: String?
  var coverage = ProjectSource.TextCoverage.complete
  var pageCount: Int?
  var unreadablePages: [Int] = []
  var omittedPages: [Int] = []
  var ocrPages: [Int] = []
  var resumePage: Int?
  var ocrFailedPages: [Int] = []
}
