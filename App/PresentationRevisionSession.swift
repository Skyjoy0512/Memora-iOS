import Foundation
import Observation

@MainActor
@Observable
final class PresentationRevisionSession {
  private(set) var isBusy = false
  private(set) var proposal: PresentationRevision?
  private(set) var failure: String?
  @ObservationIgnored private var operation: UUID?
  @ObservationIgnored private var worker: Task<AIAnswerResult, Never>?
  @ObservationIgnored private var authorization: (@MainActor () -> Bool)?

  func generate(_ request: PresentationRevision.Request,
                isCurrent: @escaping @MainActor () -> Bool,
                using generate: @escaping @MainActor () async -> AIAnswerResult) async {
    guard !isBusy else { return }
    cancel(); failure = nil
    guard isCurrent(), !Task.isCancelled else { failure = "資料または出典の権限を確認できません。"; return }
    let id = UUID(); operation = id; isBusy = true; authorization = isCurrent
    let worker = Task {
      guard !Task.isCancelled, isCurrent() else { return AIAnswerResult.failure(.contextChanged) }
      return await generate()
    }
    self.worker = worker
    let monitor = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard let self, self.operation == id else { return }
        if !isCurrent() {
          self.cancel(); self.failure = "資料・モデル・出典の許可が変更されたため停止しました。"
          return
        }
      }
    }
    defer { monitor.cancel() }
    let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    guard operation == id else { return }
    self.worker = nil; isBusy = false
    guard !Task.isCancelled, isCurrent() else { cancel(); failure = "参照情報が変わったため修正案を破棄しました。"; return }
    switch result {
    case .answer(let text):
      do { proposal = try PresentationRevision.decode(text, for: request) }
      catch { failure = error.localizedDescription }
    case .failure(let error): failure = error.message
    }
  }

  func accept(in document: MemoraDocument) throws -> MemoraDocument {
    guard !isBusy, authorization?() == true, let proposal else {
      throw PresentationToolInput.Failure(message: "修正案の参照情報が変わりました。元の資料は変更していません。")
    }
    let result = try proposal.applying(to: document)
    cancel()
    return result
  }

  func cancel() {
    operation = nil; worker?.cancel(); worker = nil; isBusy = false
    proposal = nil; authorization = nil
  }
}
