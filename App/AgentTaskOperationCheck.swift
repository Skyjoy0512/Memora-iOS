#if DEBUG
import Foundation
import Observation

/// Exercises the real approval and SQLite paths without a model or network call.
@MainActor @Observable
final class AgentTaskOperationCheck {
  var messageID: UUID?
  var result = ""
  var isRunning = false
  var savedIDs: Set<UUID> = []
  @ObservationIgnored private var task: Task<Void, Never>?

  func start(in model: MemoraModel) {
    guard !isRunning, !model.isAIChatResponding, model.pendingAgentApproval == nil,
          !model.isRestoring, !model.isStoreProtected, model.currentTeamID == nil else { return }
    guard cleanup(in: model) else { return }
    let id = UUID()
    messageID = id
    let marker = String(id.uuidString.prefix(8))
    let call = AgentToolCall(id: "local-check-" + marker, name: AgentTool.addTasks.rawValue,
      arguments: ["tasks": [["title": "QA \(marker) 見積書を確認", "detail": "操作検証用です。画面を閉じると検証データだけを削除します。"],
        ["title": "QA \(marker) 次回の未決事項を整理"]]])
    model.aiMessages.append(AIChatMessage(id: id, role: .assistant, text: "ローカル操作検証"))
    isRunning = true
    result = "モデル応答は検証用です。登録は通常と同じ承認・保存経路を通ります。"
    task = Task { [weak self, weak model] in
      guard let self, let model else { return }
      defer { self.isRunning = false; self.task = nil }
      let outcome = await model.runAgentTool(call, messageID: id, scope: .all)
      self.savedIDs = Set(model.agentMessage(id)?.createdTaskIDs ?? [])
      self.result = outcome.text
      guard !self.savedIDs.isEmpty else { return }
      if case .data(let data) = RecordStore.load(MemoraModel.StorageKey.tasks),
         let stored = try? JSONDecoder().decode([MemoraTask].self, from: data),
         self.savedIDs.allSatisfy({ identifier in
           stored.first { $0.id == identifier } == model.task(id: identifier)
         }) {
        self.result += "\nSQLite再読込一致: \(self.savedIDs.count)件。"
      } else {
        self.result += "\nSQLite再読込を確認できませんでした。"
      }
      let repeated = await model.runAgentTool(call, messageID: id, scope: .all)
      self.result += repeated.isError ? "\n同一依頼の再実行を拒否しました。" : "\n再実行の拒否を確認できませんでした。"
    }
  }

  func stop(in model: MemoraModel) {
    task?.cancel()
    if model.pendingAgentApproval?.messageID == messageID { model.resolveAgentApproval(false) }
  }

  @discardableResult
  func cleanup(in model: MemoraModel) -> Bool {
    stop(in: model)
    // Identity, never a title or prefix, limits deletion to this check's writes.
    if !savedIDs.isEmpty {
      guard model.persistNow(model.tasks.filter { !savedIDs.contains($0.id) }, forKey: MemoraModel.StorageKey.tasks) else {
        result = "検証タスクを削除できませんでした。保存先を確認してください。"
        return false
      }
      model.tasks.removeAll { savedIDs.contains($0.id) }
      savedIDs.forEach { TaskReminderScheduler.cancel(taskID: $0) }
      savedIDs = []
    }
    if let messageID {
      model.aiMessages.removeAll { $0.id == messageID }
      model.agentToolCallCounts.removeValue(forKey: messageID)
      model.agentBlockedExternalTools.removeValue(forKey: messageID)
      model.approvedAgentTaskDrafts.removeValue(forKey: messageID)
    }
    return true
  }
}
#endif
