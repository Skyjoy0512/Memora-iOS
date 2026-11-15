import Foundation

actor LocalVoiceLLM {
  static let shared = LocalVoiceLLM()
  private var context: LocalLlamaContext?
  private var isGenerating = false
  private var loadingTask: Task<LocalLlamaContext, Error>?

  func prepare() async throws {
    guard LocalVoiceModel.isInstalled else { throw LiveVoiceError.unavailable("会話モデルが未導入です。モデル画面からダウンロードしてください。") }
    guard context == nil else { return }
    if loadingTask == nil {
      loadingTask = Task { try await LocalLlamaContext.load(path: LocalVoiceModel.fileURL.path) }
    }
    defer { loadingTask = nil }
    context = try await loadingTask?.value
  }

  func answer(question: String, context references: String, history: String,
              onText: (@MainActor (String) -> Void)? = nil,
              authorize: (@MainActor () -> Bool)? = nil) async -> AIAnswerResult {
    // An interrupted native decode may still be finishing its current batch.
    // Let it release the context instead of turning a quick follow-up into an error.
    for _ in 0..<100 {
      guard isGenerating else { break }
      do { try await Task.sleep(for: .milliseconds(20)) }
      catch { return .failure(.cancelled) }
    }
    guard !isGenerating else { return .failure(.engineNotReady) }
    guard LocalVoiceModel.isInstalled else { return .failure(.notBundled) }
    isGenerating = true
    defer { isGenerating = false }
    do {
      if let authorize, await !authorize() { return .failure(.contextChanged) }
      try Task.checkCancellation()
      try await prepare()
      guard let context else { return .failure(.generationFailed) }
      try Task.checkCancellation()
      var ready = false
      for limit in [1_800, 900, 300, 0] {
        do {
          try await context.begin(prompt: LocalVoicePrompt.make(question: question, context: references, history: history, contextLimit: limit))
          ready = true
          break
        } catch LocalLlamaContext.Failure.promptTooLong { continue }
      }
      guard ready else { return .failure(.contextTooLarge) }
      var text = ""
      var decoder = LocalTokenTextBuffer()
      var reachedEnd = false
      for _ in 0..<384 {
        try Task.checkCancellation()
        if let authorize, await !authorize() { return .failure(.contextChanged) }
        guard let bytes = try await context.next() else { reachedEnd = true; break }
        let piece = try decoder.append(bytes)
        guard !piece.isEmpty else { continue }
        text += piece
        if let onText { await onText(text) }
      }
      if reachedEnd { try decoder.finish() }
      else if !text.isEmpty { text += "\n\n回答の長さの上限に達したため、ここで区切りました。" }
      try Task.checkCancellation()
      return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .failure(.empty) : .answer(text)
    } catch is CancellationError { return .failure(.cancelled) }
    catch { return .failure(.generationFailed) }
  }
}
