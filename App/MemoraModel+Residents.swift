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
      var updated = agent
      updated.lastRunAt = residentAgents[index].lastRunAt
      residentAgents[index] = updated
    } else {
      residentAgents.append(agent)
    }
    scheduleResidentRefresh()
  }

  func deleteResident(_ id: UUID) {
    residentAgents.removeAll { $0.id == id }
    scheduleResidentRefresh()
  }

  func residentDefinitionsDidChange(from previous: [ResidentAgent]) {
    for id in Set(previous.map(\.id) + residentAgents.map(\.id)) {
      var before = previous.first { $0.id == id }
      var after = residentAgents.first { $0.id == id }
      // Completion timestamps do not change the definition that authorized a run.
      before?.lastRunAt = nil
      after?.lastRunAt = nil
      if before != after { cancelResident(id) }
    }
  }

  func invalidateResidentEnvironment() {
    residentEnvironmentRevision = UUID()
    for id in Array(residentJobs.keys) { cancelResident(id) }
  }

  func invalidatePendingResidents() {
    for (id, request) in residentRunRequests where !residentRunIsCurrent(request) {
      cancelResident(id)
    }
  }

  private func residentRequest(_ agent: ResidentAgent, meetingID: UUID? = nil, automatic: Bool) -> ResidentRunRequest? {
    guard let stored = residentAgents.first(where: { $0.id == agent.id }),
          !automatic || stored.isEnabled, let llm = residentLLM else { return nil }
    let request = ResidentRunRequest(agent: agent, meetingID: meetingID, automatic: automatic,
      definitionRevision: residentDefinitionRevisions[agent.id], environmentRevision: residentEnvironmentRevision,
      workspaceGeneration: aiWorkspaceGeneration, accessRevision: residentAccessRevision,
      configurationRevision: summaryConfigurationRevision, registeredModelRevision: registeredLLMs.revision,
      llm: llm, readToolNames: Set(AgentTool.residentTools.filter { enabledAgentTools.contains($0) }.map(\.rawValue)),
      lastRunAt: stored.lastRunAt)
    return residentRunIsCurrent(request) ? request : nil
  }

  private func residentRunIsCurrent(_ request: ResidentRunRequest) -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected,
          aiWorkspaceGeneration == request.workspaceGeneration,
          residentEnvironmentRevision == request.environmentRevision,
          residentDefinitionRevisions[request.agent.id] == request.definitionRevision,
          residentAccessRevision == request.accessRevision,
          summaryConfigurationRevision == request.configurationRevision,
          registeredLLMs.revision == request.registeredModelRevision,
          residentLLM == request.llm,
          Set(AgentTool.residentTools.filter { enabledAgentTools.contains($0) }.map(\.rawValue)) == request.readToolNames,
          let stored = residentAgents.first(where: { $0.id == request.agent.id }),
          !request.automatic || stored.isEnabled,
          request.meetingID.map({ allowsRecordAccess($0, purpose: .automaticAgent) }) ?? true else { return false }
    return true
  }

  /// Snapshot the queue before its first suspension, so OFF/ON cannot revive a queued run.
  func runDueResidents() async {
    let now = Date.now
    let requests = residentAgents.filter { $0.isEnabled && $0.trigger.shouldRun(at: now, lastRunAt: $0.lastRunAt) }
      .compactMap { residentRequest($0, automatic: true) }
    for request in requests {
      guard !Task.isCancelled else { return }
      guard residentAgents.first(where: { $0.id == request.agent.id })?.lastRunAt == request.lastRunAt else { continue }
      await runResident(request)
    }
    scheduleResidentRefresh()
  }

  func runResidentsAfterMeeting(_ meetingID: UUID) {
    let requests = residentAgents.filter { $0.isEnabled && $0.trigger == .afterMeeting }
      .compactMap { residentRequest($0, meetingID: meetingID, automatic: true) }
    guard !requests.isEmpty else { return }
    Task {
      for request in requests {
        guard !Task.isCancelled else { return }
        await runResident(request)
      }
    }
  }

  /// Explicit runs may use the editor's unsaved instructions, even with scheduling off.
  @discardableResult
  func runResident(_ agent: ResidentAgent, meetingID: UUID? = nil) async -> Bool {
    guard let request = residentRequest(agent, meetingID: meetingID, automatic: false) else { return false }
    return await runResident(request)
  }

  @discardableResult
  private func runResident(_ request: ResidentRunRequest) async -> Bool {
    let id = request.agent.id
    guard !Task.isCancelled, residentJobs[id] == nil, residentRunIsCurrent(request) else { return false }
    residentRunFailures.removeValue(forKey: id)
    residentRunRequests[id] = request
    let job = Task { await executeResident(request) }
    residentJobs[id] = job
    // Keep ownership until the cancelled task settles; a late callback cannot own a replacement.
    defer { residentJobs.removeValue(forKey: id); residentRunRequests.removeValue(forKey: id) }
    return await withTaskCancellationHandler {
      await job.value
    } onCancel: { job.cancel() }
  }

  func cancelResident(_ id: UUID) {
    residentDefinitionRevisions[id] = UUID()
    residentJobs[id]?.cancel()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["resident-\(id.uuidString)"])
  }

  private func executeResident(_ request: ResidentRunRequest) async -> Bool {
    guard !Task.isCancelled, residentRunIsCurrent(request) else { return false }
    let agent = request.agent
    let llm = request.llm
    let limits = agent.executionLimits ?? ResidentExecutionLimits()
    let readTools = AgentTool.residentTools.filter {
      limits.permits($0.rawValue, availableReadTools: request.readToolNames)
    }
    guard !runningResidentIDs.contains(agent.id),
          let session = CloudAgentSession(llm: llm, system: Self.residentInstructions(agent), tools: readTools, priority: .background,
            authorize: { [weak self] in self?.residentRunIsCurrent(request) == true }) else { return false }
    runningResidentIDs.insert(agent.id)
    defer { runningResidentIDs.remove(agent.id) }

    var placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    placeholder.isAgentReply = true
    placeholder.residentName = agent.name
    placeholder.residentAgentID = agent.id
    placeholder.residentSymbol = agent.symbol
    aiMessages.append(placeholder)

    session.addUserMessage(residentOpening(agent, meetingID: request.meetingID))
    let result = await runResidentTurns(session: session, messageID: placeholder.id, limits: limits, request: request)
    guard case .answer(let raw) = result, !Task.isCancelled, residentRunIsCurrent(request),
          agentMessage(placeholder.id) != nil else {
      if residentAgents.contains(where: { $0.id == agent.id }) {
        if Task.isCancelled || !residentRunIsCurrent(request) { residentRunFailures[agent.id] = "実行を停止しました。" }
        else if case .failure(let failure) = result {
          residentRunFailures[agent.id] = failure == .cancelled ? "実行を停止しました。" : (failure == .rateLimited ? "設定した実行上限で停止しました。" : failure.message)
        }
      }
      aiMessages.removeAll { $0.id == placeholder.id }
      return false
    }
    let (text, suggestions) = Self.splitSuggestions(raw)
    updateAgentMessage(placeholder.id) {
      $0.text = text
      $0.suggestions = suggestions
      $0.isThinking = false
      $0.finishedAt = .now
      $0.details = AIAnswerDetails(scopeLabel: AIChatScope.all.scopeLabel, engineLabel: "常駐エージェント",
        modelLabel: llm.modelLabel,
        sourceCount: $0.agentSteps.filter { $0.icon == AgentTool.readRecord.icon }.count,
        generatedAt: .now)
    }
    if let index = residentAgents.firstIndex(where: { $0.id == agent.id }) { residentAgents[index].lastRunAt = .now }
    saveAIExchange(question: "\(agent.name)（\(agent.trigger.label)）", answer: text,
      scopeLabel: AIChatScope.all.scopeLabel, engineLabel: "常駐エージェント", modelLabel: llm.modelLabel)
    await notifyResidentResult(request, text: text)
    return true
  }

  private func runResidentTurns(session: CloudAgentSession, messageID: UUID, limits: ResidentExecutionLimits,
                                request: ResidentRunRequest) async -> AIAnswerResult {
    var lastText = ""
    var calls = 0
    for _ in 0..<limits.modelTurnLimit {
      guard !Task.isCancelled, residentRunIsCurrent(request) else { return .failure(.cancelled) }
      let turn: AgentTurn
      do { turn = try await session.next() }
      catch let failure as AIAnswerFailure { return .failure(failure) }
      catch { return .failure(.server) }
      guard !Task.isCancelled, residentRunIsCurrent(request) else { return .failure(.cancelled) }
      if !turn.text.isEmpty { lastText = turn.text }
      guard !turn.toolCalls.isEmpty else { return lastText.isEmpty ? .failure(.empty) : .answer(lastText) }
      var results: [(call: AgentToolCall, outcome: AgentToolOutcome)] = []
      for call in turn.toolCalls {
        guard !Task.isCancelled, residentRunIsCurrent(request) else { return .failure(.cancelled) }
        guard calls < limits.toolCallLimit else { return .failure(.rateLimited) }
        calls += 1
        let outcome = limits.permits(call.name, availableReadTools: request.readToolNames)
          ? await runAgentTool(call, messageID: messageID, scope: .all, automaticAccess: true)
          : AgentToolOutcome(text: "常駐中は記録を読むことだけができます。変更は「提案:」として書いてください。", isError: true)
        guard !Task.isCancelled, residentRunIsCurrent(request) else { return .failure(.cancelled) }
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
  private func notifyResidentResult(_ request: ResidentRunRequest, text: String) async {
    let agent = request.agent
    guard !Task.isCancelled, residentRunIsCurrent(request), (agent.executionLimits?.notifies ?? true), UIApplication.shared.applicationState != .active else { return }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    guard !Task.isCancelled, residentRunIsCurrent(request), UIApplication.shared.applicationState != .active,
          settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = agent.name
    content.body = String(text.prefix(160))
    content.userInfo = [Self.residentNotificationKey: agent.id.uuidString]
    let notification = UNNotificationRequest(identifier: "resident-\(agent.id.uuidString)", content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(notification)
    if Task.isCancelled || !residentRunIsCurrent(request) {
      let center = UNUserNotificationCenter.current()
      center.removePendingNotificationRequests(withIdentifiers: [notification.identifier])
      center.removeDeliveredNotifications(withIdentifiers: [notification.identifier])
    }
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
