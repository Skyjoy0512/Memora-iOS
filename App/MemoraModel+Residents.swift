import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

// Resident agents: named agents that work on a schedule or after a meeting,
// read the records, and post what they found to the Ask AI conversation. They
// run only on the person's own API key, never on Memora Intelligence credits
// or the on-device model, and they change nothing on their own.
extension MemoraModel {
  static let residentRefreshTaskID = "app.memora.residents.refresh"
  /// Enough to search, read a few records and write, within the short time
  /// the system gives a background refresh.
  private static let residentMaxTurns = 8

  /// The model a resident agent would run on, or nil when there is no BYOK
  /// cloud model with a key.
  var residentLLM: LLMSelection? {
    let configuration = askAIConfiguration
    guard AIEngineService.effectiveEngine(configuration.engine) == .cloud,
          !configuration.llm.isMemoraIntelligence,
          let key = KeychainStore.string(forKey: configuration.llm.keychainAccount), !key.isEmpty,
          !configuration.llm.modelID.isEmpty else { return nil }
    return configuration.llm
  }

  func updateResident(_ agent: ResidentAgent) {
    if let index = residentAgents.firstIndex(where: { $0.id == agent.id }) {
      residentAgents[index] = agent
    } else {
      residentAgents.append(agent)
    }
    scheduleResidentRefresh()
  }

  func deleteResident(_ id: UUID) {
    residentAgents.removeAll { $0.id == id }
    scheduleResidentRefresh()
  }

  /// Runs every enabled agent whose time came since it last finished. A run
  /// that was missed by more than its window is skipped rather than posted
  /// late: a morning brief at midnight helps no one.
  func runDueResidents() async {
    guard currentTeamID == nil, residentLLM != nil, !isRestoring, !isStoreProtected else { return }
    let now = Date.now
    for agent in residentAgents where agent.isEnabled {
      guard let due = agent.trigger.lastDue(before: now),
            now.timeIntervalSince(due) < agent.trigger.lateWindow,
            (agent.lastRunAt ?? .distantPast) < due else { continue }
      guard !Task.isCancelled else { return }
      await runResident(agent)
    }
    scheduleResidentRefresh()
  }

  /// Starts the agents that follow a finished meeting.
  func runResidentsAfterMeeting(_ meetingID: UUID) {
    guard currentTeamID == nil, residentLLM != nil, allowsRecordAccess(meetingID, purpose: .automaticAgent) else { return }
    let agents = residentAgents.filter { $0.isEnabled && $0.trigger == .afterMeeting }
    guard !agents.isEmpty else { return }
    Task {
      for agent in agents {
        await runResident(agent, meetingID: meetingID)
      }
    }
  }

  /// Runs one agent now and posts its result. Returns false when it could not
  /// run or did not finish; `lastRunAt` moves only on a finished run, so a run
  /// cut short by the system is tried again.
  @discardableResult
  func runResident(_ agent: ResidentAgent, meetingID: UUID? = nil) async -> Bool {
    guard !Task.isCancelled, residentJobs[agent.id] == nil else { return false }
    residentRunFailures.removeValue(forKey: agent.id)
    let job = Task { await executeResident(agent, meetingID: meetingID) }
    residentJobs[agent.id] = job
    defer { residentJobs.removeValue(forKey: agent.id) }
    return await withTaskCancellationHandler {
      await job.value
    } onCancel: { job.cancel() }
  }

  func cancelResident(_ id: UUID) { residentJobs[id]?.cancel() }

  private func executeResident(_ agent: ResidentAgent, meetingID: UUID?) async -> Bool {
    guard !Task.isCancelled else { return false }
    guard currentTeamID == nil, !isRestoring, !isStoreProtected,
          meetingID.map({ allowsRecordAccess($0, purpose: .automaticAgent) }) ?? true else { return false }
    let limits = agent.executionLimits ?? ResidentExecutionLimits()
    let readTools = AgentTool.residentTools.filter { enabledAgentTools.contains($0) }
    let allowedNames = Set(readTools.map(\.rawValue))
    guard let llm = residentLLM, !runningResidentIDs.contains(agent.id),
          let session = CloudAgentSession(
            llm: llm,
            system: Self.residentInstructions(agent),
            tools: readTools.filter { limits.permits($0.rawValue, availableReadTools: allowedNames) }
          ) else { return false }
    runningResidentIDs.insert(agent.id)
    defer { runningResidentIDs.remove(agent.id) }

    var placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    placeholder.isAgentReply = true
    placeholder.residentName = agent.name
    placeholder.residentAgentID = agent.id
    placeholder.residentSymbol = agent.symbol
    aiMessages.append(placeholder)

    session.addUserMessage(residentOpening(agent, meetingID: meetingID))
    let result = await runResidentTurns(session: session, messageID: placeholder.id, limits: limits)

    guard case .answer(let raw) = result, !Task.isCancelled, agentMessage(placeholder.id) != nil else {
      if case .failure(let failure) = result {
        residentRunFailures[agent.id] = failure == .cancelled ? "実行を停止しました。" : (failure == .rateLimited ? "設定した実行上限で停止しました。" : failure.message)
      }
      // Cut short or failed: nothing half-done stays in the conversation.
      aiMessages.removeAll { $0.id == placeholder.id }
      return false
    }
    let (text, suggestions) = Self.splitSuggestions(raw)
    updateAgentMessage(placeholder.id) {
      $0.text = text
      $0.suggestions = suggestions
      $0.isThinking = false
      $0.finishedAt = .now
      $0.details = AIAnswerDetails(
        scopeLabel: AIChatScope.all.scopeLabel,
        engineLabel: "常駐エージェント",
        modelLabel: llm.modelLabel,
        sourceCount: self.agentMessage(placeholder.id)?.agentSteps.filter { $0.icon == AgentTool.readRecord.icon }.count ?? 0,
        generatedAt: .now
      )
    }
    if let index = residentAgents.firstIndex(where: { $0.id == agent.id }) {
      residentAgents[index].lastRunAt = .now
    }
    saveAIExchange(
      question: "\(agent.name)（\(agent.trigger.label)）",
      answer: text,
      scopeLabel: AIChatScope.all.scopeLabel,
      engineLabel: "常駐エージェント",
      modelLabel: llm.modelLabel
    )
    await notifyResidentResult(agent, text: text)
    return true
  }

  /// Model turns and reading tools until the agent answers. A call to any tool
  /// it was not given is refused here too, so an unattended run cannot change
  /// data even if the model asks.
  private func runResidentTurns(session: CloudAgentSession, messageID: UUID, limits: ResidentExecutionLimits) async -> AIAnswerResult {
    let accessRevision = residentAccessRevision
    let allowed = Set(AgentTool.residentTools.filter { enabledAgentTools.contains($0) }.map(\.rawValue))
    var lastText = ""
    var calls = 0
    for _ in 0..<limits.modelTurnLimit {
      guard !Task.isCancelled, !isRestoring, !isStoreProtected,
            accessRevision == residentAccessRevision else { return .failure(.cancelled) }
      let turn: AgentTurn
      do {
        turn = try await session.next()
      } catch let failure as AIAnswerFailure {
        return .failure(failure)
      } catch {
        return .failure(.server)
      }
      guard accessRevision == residentAccessRevision else { return .failure(.cancelled) }
      if !turn.text.isEmpty { lastText = turn.text }
      guard !turn.toolCalls.isEmpty else {
        return lastText.isEmpty ? .failure(.empty) : .answer(lastText)
      }
      var results: [(call: AgentToolCall, outcome: AgentToolOutcome)] = []
      for call in turn.toolCalls {
        guard calls < limits.toolCallLimit else { return .failure(.rateLimited) }
        calls += 1
        let outcome = limits.permits(call.name, availableReadTools: allowed)
          ? await runAgentTool(call, messageID: messageID, scope: .all, automaticAccess: true)
          : AgentToolOutcome(text: "常駐中は記録を読むことだけができます。変更は「提案:」として書いてください。", isError: true)
        results.append((call, outcome))
      }
      session.addToolResults(results)
    }
    return .failure(.rateLimited)
  }

  private func residentOpening(_ agent: ResidentAgent, meetingID: UUID?) -> String {
    var parts: [String] = []
    if agent.usesMemory {
      let personal = personalContext(for: agent.instructions, budget: 2_000, includesHistory: false)
      if !personal.isEmpty { parts.append(personal) }
    }
    if let meetingID, allowsRecordAccess(meetingID, purpose: .automaticAgent), let meeting = meeting(id: meetingID) {
      parts.append("""
      終わった会議: 「\(meeting.displayTitle)」（id: \(meetingID.uuidString)）
      read_record でこの会議を読んでから作業してください。
      """)
    }
    let now = Date.now.formatted(date: .complete, time: .shortened)
    parts.append("いま: \(now)\nあなたの役割「\(agent.role)」に沿って、今回の作業をしてください。")
    return parts.joined(separator: "\n\n")
  }

  static func residentInstructions(_ agent: ResidentAgent) -> String {
    """
    あなたは記録アプリ「Memora」の常駐エージェント「\(agent.name)」です。利用者が見ていないあいだに自動で動き、結果を Ask AI の会話に投稿します。

    役割: \(agent.role)
    指示: \(agent.instructions)

    - 道具で会議の記録・タスク・プロジェクト・人物\(GmailService.shared.isConnected ? "・メール" : "")を読みます。読むことしかできません。
    - 事実は道具で読んだものだけに基づきます。記録にないことは書きません。伝えることがなければ、そう一行で書きます。
    - 結果は短くまとめます。見出しは使わず、要点を3〜5行の箇条書きにします。
    - 次にすべき変更（タスクの追加、メールの下書き、予定の登録など）は自分では行わず、最後に「提案: 」で始まる行として最大3つ書きます。各行は、利用者がそのまま送れば実行できる依頼文にします。
    - 記録やプロジェクトのidは利用者に見せません。

    \(ReadabilityGuide.rules)
    """
  }

  /// Takes the agent's 「提案:」 lines out of the reply, so they become
  /// buttons instead of text.
  static func splitSuggestions(_ text: String) -> (text: String, suggestions: [String]) {
    var body: [Substring] = []
    var suggestions: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
        .trimmingPrefix(while: { "-*・ ".contains($0) })
      if let range = trimmed.range(of: #"^提案[:：]\s*"#, options: .regularExpression) {
        let suggestion = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
        if !suggestion.isEmpty, suggestions.count < 3 { suggestions.append(suggestion) }
      } else {
        body.append(line)
      }
    }
    let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return (joined, suggestions)
  }

  /// A notice for a result that arrived while the app was away, only when the
  /// person already allowed notifications; a background run never asks.
  private func notifyResidentResult(_ agent: ResidentAgent, text: String) async {
    guard (agent.executionLimits?.notifies ?? true), UIApplication.shared.applicationState != .active else { return }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = agent.name
    content.body = String(text.prefix(160))
    content.userInfo = [Self.residentNotificationKey: agent.id.uuidString]
    let request = UNNotificationRequest(identifier: "resident-\(agent.id.uuidString)", content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(request)
  }

  static let residentNotificationKey = "memora.resident"

  // MARK: - Background refresh

  /// Asks the system to wake the app around the next scheduled run. The
  /// system decides the real time, so a run can come later than asked.
  func scheduleResidentRefresh() {
    let now = Date.now
    let next = residentAgents
      .filter(\.isEnabled)
      .compactMap { $0.trigger.nextDue(after: now) }
      .min()
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.residentRefreshTaskID)
    guard let next, residentLLM != nil else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.residentRefreshTaskID)
    request.earliestBeginDate = next
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Runs due agents in a background refresh, stopping when the system says
  /// time is up.
  func handleResidentRefresh(_ task: BGAppRefreshTask) {
    let work = Task {
      await runDueResidents()
      task.setTaskCompleted(success: !Task.isCancelled)
    }
    task.expirationHandler = { work.cancel() }
  }
}
