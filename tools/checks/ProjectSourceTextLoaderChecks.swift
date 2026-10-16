import Foundation

@main
@MainActor
enum ProjectSourceTextLoaderChecks {
  static func main() async {
    let gate = SourceReaderGate()
    let loader = ProjectSourceTextLoader { try await gate.read($0) }
    let a = UUID(), b = UUID()
    func request(_ id: UUID, _ reference: String?, retry: Int = 0) -> ProjectSourceTextRequest {
      .init(sourceID: id, reference: reference, retry: retry)
    }
    let first = Task { await loader.load(request(a, "A")) }
    await gate.waitForRead(1)
    let second = Task { await loader.load(request(b, "B")) }
    await gate.waitForRead(2)
    precondition(loader.snapshot.value(for: a) == nil && loader.snapshot.state == .loading)
    await gate.finish(1, text: "late A")
    await first.value
    precondition(loader.snapshot.key == b && loader.snapshot.state == .loading)
    await gate.finish(2, text: "B")
    await second.value
    precondition(loader.snapshot.value?.first?.text == "B")

    let refresh = Task { await loader.load(request(b, "B", retry: 1)) }
    await gate.waitForRead(3)
    precondition(loader.snapshot.state == .refreshing && loader.snapshot.value?.first?.text == "B")
    loader.stop()
    precondition(loader.snapshot.state == .failed && loader.snapshot.activityID == nil)
    precondition(loader.snapshot.failure?.contains("停止") == true)
    await gate.finish(3, text: "late after stop")
    await refresh.value
    precondition(loader.snapshot.state == .failed && loader.snapshot.value?.first?.text == "B")

    let retry = Task { await loader.load(request(b, "B", retry: 2)) }
    await gate.waitForRead(4)
    await gate.finish(4, text: "new B")
    await retry.value
    precondition(loader.snapshot.state == .loaded && loader.snapshot.failure == nil)
    precondition(loader.snapshot.value?.first?.text == "new B")

    let invalidated = Task { await loader.load(request(b, "B", retry: 3), isCurrent: { false }) }
    await gate.waitForRead(5)
    await gate.finish(5, text: "changed reference")
    await invalidated.value
    precondition(loader.snapshot.value?.first?.text == "new B")

    let failed = Task { await loader.load(request(b, "missing")) }
    await gate.waitForRead(6)
    await gate.fail(6)
    await failed.value
    precondition(loader.snapshot.state == .failed && loader.snapshot.value?.first?.text == "new B")

    let empty = Task { await loader.load(request(b, "empty")) }
    await gate.waitForRead(7)
    await gate.finish(7, text: nil)
    await empty.value
    precondition(loader.snapshot.state == .empty)

    let cancelled = Task { await loader.load(request(b, "empty")) }
    await gate.waitForRead(8)
    cancelled.cancel()
    await gate.finish(8, text: "late on navigation")
    await cancelled.value
    precondition(loader.snapshot.state == .empty && loader.snapshot.value == [])

    let oldFailure = Task { await loader.load(request(a, "bad")) }
    await gate.waitForRead(9)
    let latest = Task { await loader.load(request(b, "good")) }
    await gate.waitForRead(10)
    await gate.fail(9)
    await oldFailure.value
    precondition(loader.snapshot.state == .loading && loader.snapshot.failure == nil)
    loader.stop()
    precondition(loader.snapshot.state == .failed)
    await gate.finish(10, text: "late after second stop")
    await latest.value
    precondition(loader.snapshot.value == nil && loader.snapshot.state == .failed)

    await loader.load(request(a, nil))
    precondition(loader.snapshot.state == .empty && loader.snapshot.value == [])
    let noRead = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      await loader.load(request(b, "never"))
    }
    await noRead.value
    let reads = await gate.readCount()
    precondition(reads == 10)
    print("ProjectSourceTextLoaderChecks: passed (real loader with suspended mock reads: overlap, immediate stop, late success/failure, retry, refresh, reference change, parent cancellation, nil/empty; no files or network)")
  }
}

private actor SourceReaderGate {
  private var count = 0
  private var pending: [Int: CheckedContinuation<[ProjectSourceText], any Error>] = [:]
  private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]

  func read(_ reference: String) async throws -> [ProjectSourceText] {
    count += 1
    let id = count
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      arrivals.removeValue(forKey: id)?.resume()
    }
  }

  func waitForRead(_ id: Int) async {
    if pending[id] != nil { return }
    await withCheckedContinuation { arrivals[id] = $0 }
  }

  func finish(_ id: Int, text: String?) {
    pending.removeValue(forKey: id)!.resume(returning: text.map { [ProjectSourceText(text: $0)] } ?? [])
  }

  func fail(_ id: Int) { pending.removeValue(forKey: id)!.resume(throwing: Failure.unreadable) }
  func readCount() -> Int { count }
  private enum Failure: Error { case unreadable }
}
