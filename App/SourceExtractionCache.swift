import CryptoKit
import Foundation

actor SourceExtractionCache {
  #if !MEMORA_HOST_CHECKS
  static let shared = SourceExtractionCache(persistenceDirectory: SourceExtractionPersistence.directory) {
    try await SourceIntake.extract($0, vocabulary: $1)
  }
  #endif

  private var results: [String: ProjectSourceExtractionResult] = [:]
  private var jobs: [String: ExtractionJob] = [:]
  private var generation = UUID()
  private let extraction: @Sendable (URL, [String]) async throws -> ProjectSourceExtractionResult
  private let persistence: SourceExtractionPersistence?

  init(persistenceDirectory: URL? = nil, now: @escaping () -> Date = Date.init,
       extraction: @escaping @Sendable (URL, [String]) async throws -> ProjectSourceExtractionResult) {
    self.extraction = extraction
    persistence = persistenceDirectory.map { SourceExtractionPersistence(directory: $0, now: now) }
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
    // Bump the extractor version whenever extraction semantics change. Locale
    // and OS changes can alter OCR/speech output even for identical originals.
    let system = ProcessInfo.processInfo.operatingSystemVersion
    let key = "v2.\(system.majorVersion).\(system.minorVersion).\(Locale.current.identifier)."
      + digest + "." + suffix + "." + vocabularyDigest
    guard try attributes(url) == before else { throw ProjectSourceFiles.Failure.invalidFile }
    if let cached = results[key], cached.resumePage == nil { return cached }
    if let cached = persistence?.read(key), cached.resumePage == nil {
      try Task.checkCancellation()
      guard try attributes(url) == before, try fingerprint(url) == digest else {
        throw ProjectSourceFiles.Failure.invalidFile
      }
      remember(cached, key: key)
      return cached
    }
    let epoch = generation
    let job: ExtractionJob
    if let existing = jobs[key] { job = existing }
    else {
      let extraction = self.extraction
      job = ExtractionJob(task: Task {
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
    job.waiters += 1
    defer {
      job.waiters -= 1
      if job.waiters == 0, jobs[key]?.id == job.id { jobs.removeValue(forKey: key) }
    }
    let result = try await job.task.value
    try Task.checkCancellation()
    guard epoch == generation, job.isValid, try attributes(url) == before,
          try fingerprint(url) == digest else { throw ProjectSourceFiles.Failure.invalidFile }
    // Only successful local extraction is reusable. A failed speech engine or
    // unavailable format must be attempted again when the person retries.
    if !job.hasPublished {
      job.hasPublished = true
      remember(result, key: key)
      if !result.blocks.isEmpty, result.resumePage == nil { persistence?.write(key, result: result) }
    }
    return result
  }

  private func remember(_ result: ProjectSourceExtractionResult, key: String) {
    let bytes = result.blocks.reduce(0) { $0 + $1.text.utf8.count } + (result.thumbnail?.count ?? 0)
    if results[key] == nil, !result.blocks.isEmpty, result.resumePage == nil, bytes <= 4 * 1024 * 1024 {
      if results.count >= 6 || results.values.reduce(0, { $0 + $1.blocks.reduce(0) { $0 + $1.text.utf8.count } + ($1.thumbnail?.count ?? 0) }) + bytes > 12 * 1024 * 1024 {
        results = [:]
      }
      results[key] = result
    }
  }

  func clear() {
    generation = UUID()
    for job in jobs.values { job.isValid = false; job.task.cancel() }
    jobs = [:]
    clearStoredResults()
  }

  /// For old records without fingerprints, purge settled derivations while
  /// unrelated imports finish normally. The deleted record's caller is cancelled
  /// by its owner before this call and cannot publish after its await returns.
  func clearStoredResults() {
    results = [:]
    persistence?.clear()
  }

  /// Deletion removes every format/vocabulary variant of the original, without
  /// cancelling work on unrelated sources. Pending callers cannot republish it.
  func invalidate(fingerprints: Set<String>) {
    let values = Set(fingerprints.map { $0.lowercased() }.filter {
      $0.utf8.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) }
    })
    guard !values.isEmpty else { return }
    func matches(_ key: String) -> Bool { values.contains { key.contains(".\($0).") } }
    results = results.filter { !matches($0.key) }
    for key in jobs.keys.filter(matches) {
      if let job = jobs.removeValue(forKey: key) { job.isValid = false; job.task.cancel() }
    }
    persistence?.invalidate(fingerprints: values)
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

  private final class ExtractionJob {
    var id = UUID()
    var task: Task<ProjectSourceExtractionResult, Error>
    var hasPublished = false
    var isValid = true
    var waiters = 0
    init(task: Task<ProjectSourceExtractionResult, Error>) { self.task = task }
  }
}
