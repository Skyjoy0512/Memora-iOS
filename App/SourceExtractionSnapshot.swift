import Foundation

/// Derived text has no authority of its own: callers still supply and hash an
/// accessible original before a snapshot can be reused.
struct SourceExtractionSnapshot: Codable {
  var version = 1
  var blocks: [ProjectSourceText]
  var notice: String?
  var coverage: ProjectSource.TextCoverage
  var pageCount: Int?
  var unreadablePages: [Int]
  var omittedPages: [Int]
  var ocrPages: [Int]
  var thumbnailReference: String?
  var thumbnailFingerprint: String?
  var resumePage: Int?

  init(_ result: ProjectSourceExtractionResult, thumbnailReference: String?, thumbnailFingerprint: String?) {
    blocks = result.blocks
    notice = result.notice
    coverage = result.coverage
    pageCount = result.pageCount
    unreadablePages = result.unreadablePages
    omittedPages = result.omittedPages
    ocrPages = result.ocrPages
    self.thumbnailReference = thumbnailReference
    self.thumbnailFingerprint = thumbnailFingerprint
    resumePage = result.resumePage
  }

  func result(thumbnail: Data?) -> ProjectSourceExtractionResult? {
    guard version == 1, !blocks.isEmpty,
          blocks.reduce(0, { $0 + $1.text.utf8.count }) <= ProjectSourceTextReader.maximumBytes,
          blocks.allSatisfy({ ($0.page ?? 1) > 0 && ($0.time == nil || ($0.time!.isFinite && $0.time! >= 0)) }),
          (pageCount ?? 1) > 0,
          (resumePage == nil || (resumePage! > 1 && resumePage! <= 2_000 &&
            resumePage! <= (pageCount ?? 0) && omittedPages.first == resumePage)),
          (unreadablePages + omittedPages + ocrPages).allSatisfy({ $0 > 0 }) else { return nil }
    return .init(blocks: blocks, thumbnail: thumbnail, notice: notice, coverage: coverage,
      pageCount: pageCount, unreadablePages: unreadablePages, omittedPages: omittedPages, ocrPages: ocrPages,
      resumePage: resumePage)
  }
}
