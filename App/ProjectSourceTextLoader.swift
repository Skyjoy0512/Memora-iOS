import Foundation
import Observation

@MainActor
@Observable
final class ProjectSourceTextLoader {
  typealias Reader = @Sendable (String) async throws -> [ProjectSourceText]

  private(set) var snapshot = MemoraLoadSnapshot<UUID, [ProjectSourceText]>()
  @ObservationIgnored private var job: Task<Void, Never>?
  @ObservationIgnored private var jobID: UUID?
  @ObservationIgnored private var reader: Reader

  init(reader: @escaping Reader = { try await ProjectSourceTextReader.readAsync($0) }) {
    self.reader = reader
  }

  func load(_ request: ProjectSourceTextRequest, isCurrent: @escaping @MainActor () -> Bool = { true }) async {
    guard !Task.isCancelled else { return }
    job?.cancel()
    let token = snapshot.begin(request.sourceID)
    jobID = token
    let work = Task { [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { snapshot.cancel(token); return }
      guard let reference = request.reference else {
        snapshot.finish([], isEmpty: true, token: token)
        return
      }
      do {
        let blocks = try await reader(reference)
        try Task.checkCancellation()
        guard isCurrent() else { snapshot.cancel(token); return }
        snapshot.finish(blocks, isEmpty: blocks.isEmpty, token: token)
      } catch {
        if Task.isCancelled { snapshot.cancel(token) }
        else { snapshot.fail("保存された本文を読み込めませんでした。ファイルが見つからないか、読み取れない形式です。", token: token) }
      }
    }
    job = work
    await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    if jobID == token { job = nil; jobID = nil }
  }

  func stop() {
    guard let token = jobID else { return }
    // Invalidate before cancellation: a reader can settle after the person stops it.
    snapshot.fail("本文の読み込みを停止しました。", token: token)
    job?.cancel()
  }
}
