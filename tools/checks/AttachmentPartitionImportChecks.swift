import Foundation

@main struct AttachmentPartitionImportChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let original = root.appendingPathComponent("original.pdf")
    try Data("original remains intact".utf8).write(to: original)
    PDFSourcePartitioning.parts = try (0..<3).map { index in
      let url = root.appendingPathComponent("part-\(index).pdf")
      try Data("native part \(index)".utf8).write(to: url)
      return .init(url: url, firstPage: index * 100 + 1, lastPage: (index + 1) * 100)
    }
    let model = MemoraModel()
    let success = try await model.importAIAttachment(from: original, maximumFiles: 3)
    precondition(success.files.count == 3 && success.displayName == "original.pdf")
    precondition(success.files.map { $0.sourceMetadata?["partitionFirstPage"] } == ["1", "101", "201"])
    precondition(success.files.allSatisfy { $0.url.deletingLastPathComponent() == AIAttachmentFiles.directory })
    precondition(PDFSourcePartitioning.requestedMaximum == 3 && PDFSourcePartitioning.cleanupCount == 1)
    let reference = AIAttachmentFileReference(success)!
    let restored = try JSONDecoder().decode(AIAttachmentFileReference.self, from: JSONEncoder().encode(reference))
    precondition(restored.sourceMetadata == success.sourceMetadata && restored.additionalFiles?.last?.sourceMetadata == success.files.last?.sourceMetadata)
    await AIAttachmentFiles.shared.reset()

    do { _ = try await model.importAIAttachment(from: original, maximumFiles: 2); preconditionFailure("Parts silently truncated") } catch {}
    precondition(awaitCopyCount() == 0 && PDFSourcePartitioning.requestedMaximum == 2)
    do { _ = try await model.importAIAttachment(from: original, maximumFiles: 0); preconditionFailure("No-capacity import accepted") } catch {}
    precondition(awaitCopyCount() == 0)

    await AIAttachmentFiles.shared.reset(failureAt: 2)
    do { _ = try await model.importAIAttachment(from: original); preconditionFailure("Failed copy accepted") } catch {}
    try assertNoCopies()
    precondition(PDFSourcePartitioning.cleanupCount == 2)

    await AIAttachmentFiles.shared.reset(cancellationAt: 2)
    let canceled = Task { @MainActor in
      do { _ = try await model.importAIAttachment(from: original); return false }
      catch is CancellationError { return true }
      catch { return false }
    }
    let wasCanceled = await canceled.value
    precondition(wasCanceled)
    try assertNoCopies()
    precondition(PDFSourcePartitioning.cleanupCount == 3)

    await AIAttachmentFiles.shared.reset()
    PDFSourcePartitioning.needsPartition = false
    let ordinary = try await model.importAIAttachment(from: original, maximumFiles: 1)
    precondition(ordinary.files.count == 1 && ordinary.sourceMetadata == nil)
    let originalBytes = try Data(contentsOf: original)
    precondition(originalBytes == Data("original remains intact".utf8))
    print("AttachmentPartitionImportChecks: PASS. Production import method with fixture partition/copy services: caller capacity, complete part provenance, reference round trip, second-copy failure/cancellation rollback, unchanged original and ordinary import. No actual PDFKit, speech, device, network or UI claim.")
  }

  @MainActor static func assertNoCopies() throws {
    let copies = try FileManager.default.contentsOfDirectory(atPath: AIAttachmentFiles.directory.path)
    precondition(copies.isEmpty, "Partial attachment copies were retained")
  }

  // The fixture service records synchronously because this isolated check runs on MainActor.
  @MainActor static func awaitCopyCount() -> Int { ProjectSourceFiles.copyCount }
}

@MainActor final class MemoraModel {}

@MainActor enum PDFSourcePartitioning {
  static var parts: [PDFSourcePartition.Part] = []
  static var needsPartition = true, requestedMaximum = 0, cleanupCount = 0
  static func requiresPartition(_ url: URL) throws -> Bool { needsPartition }
  static func prepare(_ url: URL, maximumParts: Int) async throws -> PDFSourcePartition {
    requestedMaximum = maximumParts
    guard parts.count <= maximumParts else { throw PDFSourcePartitionFailure.partLimit }
    return .init(parts: parts)
  }
}

@MainActor struct PDFSourcePartition {
  struct Part { var url: URL; var firstPage: Int; var lastPage: Int }
  var parts: [Part]
  func cleanup() { PDFSourcePartitioning.cleanupCount += 1 }
  func metadata(for part: Part) -> [String: String] {
    ["partitionOriginalFingerprint": String(repeating: "a", count: 64),
      "partitionOriginalName": "original.pdf", "partitionOriginalPageCount": "300",
      "partitionFirstPage": String(part.firstPage), "partitionLastPage": String(part.lastPage)]
  }
}

@MainActor enum AIAttachmentFiles {
  static var directory: URL { URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AIAttachments") }
  static let shared = ProjectSourceFiles()
  static func url(_ reference: String) throws -> URL { directory.appendingPathComponent(reference) }
}

@MainActor final class ProjectSourceFiles {
  struct Receipt { var reference: String }
  enum Failure: Error { case invalidFile }
  static var copyCount = 0
  var failureAt: Int?, cancellationAt: Int?
  func copy(_ source: URL) async throws -> Receipt {
    Self.copyCount += 1
    if failureAt == Self.copyCount { throw Failure.invalidFile }
    try FileManager.default.createDirectory(at: AIAttachmentFiles.directory, withIntermediateDirectories: true)
    let name = UUID().uuidString + ".pdf"
    try FileManager.default.copyItem(at: source, to: AIAttachmentFiles.directory.appendingPathComponent(name))
    if cancellationAt == Self.copyCount { withUnsafeCurrentTask { $0?.cancel() } }
    return .init(reference: name)
  }
  func remove(_ names: [String]) async {
    for name in names { try? FileManager.default.removeItem(at: AIAttachmentFiles.directory.appendingPathComponent(name)) }
  }
  func reset(failureAt: Int? = nil, cancellationAt: Int? = nil) async {
    if let files = try? FileManager.default.contentsOfDirectory(atPath: AIAttachmentFiles.directory.path) { await remove(files) }
    Self.copyCount = 0
    self.failureAt = failureAt
    self.cancellationAt = cancellationAt
  }
}

enum PDFSourcePartitionFailure: Error { case partLimit }
enum ConversationSourceIntake {
  enum Failure: Error { case unavailable(String) }
}
