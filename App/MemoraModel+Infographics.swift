import Foundation

extension MemoraModel {
  func generateMeetingInfographic(_ snapshot: MeetingSummaryPosterSnapshot,
    configuration: (engine: AIEngine, llm: LLMSelection), cloudConsent: Bool) async throws {
    let engine = AIEngineService.effectiveEngine(configuration.engine)
    guard snapshot.isCurrent(in: self), !Task.isCancelled else { throw CancellationError() }
    if engine == .cloud {
      guard RecordAccessPolicy.allows(snapshot.privacy, purpose: .cloudAI, explicitCloudConsent: cloudConsent) else {
        throw InfographicError.message(RecordAccessPolicy.refusal)
      }
    }
    guard snapshot.summary.count <= min(30_000, AIEngineService.contextCharacterLimit(for: engine)) else {
      throw InfographicError.message("この要約は図解生成で扱える長さを超えています。本文はそのまま利用できます。")
    }
    let result: AIAnswerResult
    if engine == .cloud {
      result = await CloudAIService.complete(system: MeetingInfographicPrompt.system,
        user: "以下は資料です。\n<summary>\n\(snapshot.summary)\n</summary>", llm: configuration.llm, maximumOutputTokens: 4_200)
    } else {
      result = await AIEngineService.answer(engine: engine, llm: configuration.llm,
        question: MeetingInfographicPrompt.system, scopeLabel: "この会議の要約のみ", context: snapshot.summary, history: "")
    }
    guard !Task.isCancelled, snapshot.isCurrent(in: self) else { throw CancellationError() }
    guard let text = result.text else { throw InfographicError.message(result.failure?.message ?? "図解を生成できませんでした。") }
    let content = try MeetingInfographicPrompt.parse(text, summary: snapshot.summary)
    let document = MeetingInfographic(meetingID: snapshot.meetingID, sourceSummary: snapshot.summary,
      privacy: snapshot.privacy, modelLabel: engine == .cloud ? configuration.llm.modelLabel : "オンデバイスAI",
      generatedAt: .now, content: content)
    let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
    guard snapshot.isCurrent(in: self), !Task.isCancelled else { throw CancellationError() }
    guard await commitMeetingChange(snapshot.meetingID, change: { $0.summaryInfographicJSON = json }) else {
      throw InfographicError.message("図解を保存できませんでした。元の要約と既存の図解は保持されています。もう一度お試しください。")
    }
  }
}

private enum InfographicError: LocalizedError {
  case message(String)
  var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
