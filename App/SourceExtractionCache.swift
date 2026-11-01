import CryptoKit
import Foundation

actor SourceExtractionCache {
  #if !MEMORA_HOST_CHECKS
  static let shared = SourceExtractionCache { try await SourceIntake.extract($0, vocabulary: $1) }
  #endif

  private var results: [String: ProjectSourceExtractionResult] = [:]
  private var jobs: [String: (id: UUID, task: Task<ProjectSourceExtractionResult, Error>)] = [:]
  private var generation = UUID()
  private let extraction: @Sendable (URL, [String]) async throws -> ProjectSourceExtractionResult

  init(extraction: @escaping @Sendable (URL, [String]) async throws -> ProjectSourceExtractionResult) {
    self.extraction = extraction
  }

  func extract(_ url: URL, vocabulary: [String] = []) async throws -> ProjectSourceExtractionResult {
    try Task.checkCancellation()
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let before = try attributes(url)
    let digest = try fingerprint(url)
    let suffix = url.pathExtension.lowercased()
    let terms = [.audio, .video].contains(SourceIntake.kind(for: url)) ? vocabulary : []
    let vocabularyDigest = SHA256.hash(data: try JSONEncoder().encode(terms)).map { String(format: "%02x", $0) }.joined()
    let key = digest + "." + suffix + "." + vocabularyDigest
    guard try attributes(url) == before else { throw ProjectSourceFiles.Failure.invalidFile }
    if let cached = results[key] { return cached }
    let epoch = generation
    let job: (id: UUID, task: Task<ProjectSourceExtractionResult, Error>)
    if let existing = jobs[key] { job = existing }
    else {
      let extraction = self.extraction
      job = (UUID(), Task {
        if suffix == "memorasource" {
          let snapshot = try JSONDecoder().decode(ConversationLinkSnapshot.self, from: Data(contentsOf: url))
          guard snapshot.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= ProjectSourceTextReader.maximumBytes else {
            throw ProjectSourceFiles.Failure.extractedTextTooLarge
          }
          return .init(blocks: snapshot.blocks, notice: snapshot.notice, coverage: .partial)
        }
        return try await extraction(url, vocabulary)
      })
      jobs[key] = job
    }
    defer { if jobs[key]?.id == job.id { jobs.removeValue(forKey: key) } }
    let result = try await job.task.value
    try Task.checkCancellation()
    guard epoch == generation, try attributes(url) == before,
          try fingerprint(url) == digest else { throw ProjectSourceFiles.Failure.invalidFile }
    // Only successful local extraction is reusable. A failed speech engine or
    // unavailable format must be attempted again when the person retries.
    let bytes = result.blocks.reduce(0) { $0 + $1.text.utf8.count } + (result.thumbnail?.count ?? 0)
    if results[key] == nil, !result.blocks.isEmpty, bytes <= 4 * 1024 * 1024 {
      if results.count >= 6 || results.values.reduce(0, { $0 + $1.blocks.reduce(0) { $0 + $1.text.utf8.count } + ($1.thumbnail?.count ?? 0) }) + bytes > 12 * 1024 * 1024 {
        results = [:]
      }
      results[key] = result
    }
    return result
  }

  func clear() {
    generation = UUID()
    results = [:]
    for job in jobs.values { job.task.cancel() }
    jobs = [:]
  }

  private func attributes(_ url: URL) throws -> Attributes {
    guard url.isFileURL else { throw ProjectSourceFiles.Failure.invalidFile }
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else {
      throw ProjectSourceFiles.Failure.invalidFile
    }
    guard size <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    return Attributes(modified: values.contentModificationDate, bytes: size)
  }

  private func fingerprint(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256(), count = 0
    while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
      try Task.checkCancellation()
      count += bytes.count
      guard count <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
      digest.update(data: bytes)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private struct Attributes: Equatable {
    var modified: Date?
    var bytes: Int
  }
}
