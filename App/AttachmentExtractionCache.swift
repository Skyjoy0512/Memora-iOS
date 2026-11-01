import Foundation

actor AttachmentExtractionCache {
  static let shared = AttachmentExtractionCache()
  private var results: [URL: (modified: Date?, bytes: Int, result: ProjectSourceExtractionResult)] = [:]

  func extract(_ url: URL) async throws -> ProjectSourceExtractionResult {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
          size <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    if let cached = results[url], cached.modified == values.contentModificationDate, cached.bytes == size { return cached.result }
    let result: ProjectSourceExtractionResult
    if url.pathExtension == "memorasource" {
      let snapshot = try JSONDecoder().decode(ConversationLinkSnapshot.self, from: Data(contentsOf: url))
      guard snapshot.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
      result = .init(blocks: snapshot.blocks, notice: snapshot.notice, coverage: .partial)
    } else { result = try await SourceIntake.extract(url) }
    try Task.checkCancellation()
    let after = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    guard after.contentModificationDate == values.contentModificationDate, after.fileSize == size else { throw ProjectSourceFiles.Failure.invalidFile }
    // A small disposable cache is never another authoritative record store.
    let resultBytes = result.blocks.reduce(0) { $0 + $1.text.utf8.count }
    if resultBytes <= 4 * 1024 * 1024 {
      if results.count >= 6 || results.values.reduce(0, { $0 + $1.result.blocks.reduce(0) { $0 + $1.text.utf8.count } }) + resultBytes > 12 * 1024 * 1024 { results = [:] }
      results[url] = (values.contentModificationDate, size, result)
    }
    return result
  }

  func clear() { results = [:] }
}
