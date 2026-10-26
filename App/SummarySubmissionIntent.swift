import Foundation

/// An in-memory instruction made by Generate. It is never restored from SQLite.
@MainActor
final class SummarySubmissionIntent {
  let jobID = UUID()
  let meetingID: UUID
  let inputFingerprint: String?
  let workspaceGeneration: UUID
  let engine: AIEngine
  let llm: LLMSelection
  private var consumed = false

  init(meetingID: UUID, inputFingerprint: String?, workspaceGeneration: UUID,
    engine: AIEngine, llm: LLMSelection) {
    self.meetingID = meetingID
    self.inputFingerprint = inputFingerprint
    self.workspaceGeneration = workspaceGeneration
    self.engine = engine
    self.llm = llm
  }

  func consume() -> Bool {
    guard !consumed else { return false }
    consumed = true
    return true
  }

  func matches(meetingID: UUID, fingerprint: String?, workspace: UUID,
    engine: AIEngine, llm: LLMSelection) -> Bool {
    !consumed && inputFingerprint != nil && self.meetingID == meetingID && inputFingerprint == fingerprint
      && workspaceGeneration == workspace && self.engine == engine && self.llm == llm
  }
}
