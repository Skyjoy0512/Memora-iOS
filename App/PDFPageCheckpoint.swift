import Foundation

struct PDFPageCheckpoint: Codable {
  var page: Int
  var blocks: [ProjectSourceText]
  var usedOCR: Bool
  var unreadable: Bool
  var ocrFailed: Bool?

  var encodedBytes: Int { (try? JSONEncoder().encode(blocks).count) ?? Int.max }

  func isValid(for pageCount: Int) -> Bool {
    page > 0 && page <= pageCount && ocrFailed != true && encodedBytes <= 8 * 1024 * 1024 &&
      unreadable == blocks.isEmpty && blocks.allSatisfy { $0.page == page && $0.time == nil }
  }
}
