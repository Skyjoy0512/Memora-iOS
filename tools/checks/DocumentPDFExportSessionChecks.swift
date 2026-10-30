import Foundation

@main struct DocumentPDFExportSessionChecks {
  @MainActor static func main() async throws {
    let session = DocumentPDFExportSession()
    var successes: [URL] = [], failures: [String] = []
    var isCurrent = true
    func start() {
      session.start(document: MemoraDocument(), isCurrent: { isCurrent },
        completed: { successes.append($0) }, failed: { failures.append($0) })
    }
    start()
    await wait { DocumentPDF.requests.count == 1 }
    let first = DocumentPDF.requests[0]
    first.progress(.writing(completed: 1, total: 9))
    precondition(session.progress == .writing(completed: 1, total: 9))
    first.progress(.preparing)
    first.progress(.writing(completed: 0, total: 9))
    precondition(session.progress == .writing(completed: 1, total: 9), "out-of-order progress regressed")
    session.cancel()
    precondition(!session.isRunning && session.progress == nil)
    start()
    await wait { DocumentPDF.requests.count == 2 }
    let second = DocumentPDF.requests[1]
    first.progress(.writing(completed: 8, total: 9))
    precondition(session.progress == .preparing, "late progress modified replacement")
    let oldURL = try file()
    first.continuation.resume(returning: oldURL)
    await wait { !FileManager.default.fileExists(atPath: oldURL.path) }
    precondition(session.isRunning && successes.isEmpty && failures.isEmpty)
    let newURL = try file()
    second.continuation.resume(returning: newURL)
    await wait { successes.count == 1 }
    precondition(successes == [newURL] && !session.isRunning)
    ArtifactExportFile.removeTemporary(successes)
    successes = []
    start()
    await wait { DocumentPDF.requests.count == 3 }
    let stale = DocumentPDF.requests[2]
    isCurrent = false
    let staleURL = try file()
    stale.continuation.resume(returning: staleURL)
    await wait { !session.isRunning }
    precondition(!FileManager.default.fileExists(atPath: staleURL.path) && successes.isEmpty && failures.isEmpty)
    start()
    precondition(failures.count == 1 && DocumentPDF.requests.count == 3, "invalid source started work")
    failures = []
    isCurrent = true
    start()
    await wait { DocumentPDF.requests.count == 4 }
    let failing = DocumentPDF.requests[3]
    failing.continuation.resume(throwing: CocoaError(.fileWriteOutOfSpace))
    await wait { !session.isRunning }
    precondition(failures.count == 1 && successes.isEmpty)
    print("DocumentPDFExportSessionChecks passed: cancel/retry, late success/progress, replacement isolation, source/workspace invalidation, cleanup, honest failure, no automatic share after cancel")
  }

  @MainActor static func wait(_ predicate: () -> Bool) async {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    preconditionFailure("condition never settled")
  }

  static func file() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memora-session-check-\(UUID()).pdf")
    try Data("fixture only".utf8).write(to: url)
    return url
  }
}

struct MemoraDocument {}
@MainActor enum DocumentPDF {
  struct Request {
    var progress: @MainActor @Sendable (DocumentPDFProgress) -> Void
    var continuation: CheckedContinuation<URL, Error>
  }
  static var requests: [Request] = []
  static func write(_ document: MemoraDocument,
                    onProgress: @escaping @MainActor @Sendable (DocumentPDFProgress) -> Void) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in requests.append(Request(progress: onProgress, continuation: continuation)) }
  }
}
