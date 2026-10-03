import Foundation
import FoundationModels

// The Ask AI agent: a model that reads the records through tools and, once the
// person approves, makes documents, tasks, projects, events and memos. It runs
// on the chosen cloud model, or on Apple's on-device model with no key at all.
extension MemoraModel {
  /// Enough rounds to search, read several records and write the result, but
  /// bounded so a confused model cannot loop forever.
  private static let agentMaxTurns = 16

  /// Hands a request to the agent. Returns false while another answer is on its
  /// way, so the composer keeps the text.
  @discardableResult
  func sendAgentChat(_ request: String, attachment: AIAttachment? = nil) -> Bool {
    let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isAIChatResponding else { return false }

    let configuration = askAIConfiguration
    let scope = aiScope
    let history = aiConversationContext()
    aiMessages.append(AIChatMessage(role: .user, text: trimmed))

    let llm = configuration.llm
    let runner: AgentRunner
    switch AIEngineService.effectiveEngine(configuration.engine) {
    case .cloud:
      guard let session = CloudAgentSession(llm: llm, system: Self.agentInstructions(scope: scope)) else {
        aiMessages.append(AIChatMessage(role: .assistant, text: AIAnswerFailure.missingKey.message))
        return true
      }
      runner = .cloud(session)
    case .foundation where Self.isOnDeviceAgentAvailable:
      runner = .onDevice
    default:
      aiMessages.append(AIChatMessage(
        role: .assistant,
        text: "この端末ではエージェントを動かせるAIがありません。Apple Intelligenceを有効にするか、設定の「AI整理」でクラウド（BYOK）を選んでください。"
      ))
      return true
    }

    if attachment != nil {
      aiMessages.append(AIChatMessage(
        role: .assistant,
        text: "エージェントは添付をまだ読めません。添付なしで作業します。"
      ))
    }

    let requestID = UUID()
    aiChatRequestID = requestID
    let placeholder = AIChatMessage(role: .assistant, text: "", isThinking: true)
    aiMessages.append(placeholder)
    isAIChatResponding = true

    // The on-device window is small, so it gets only the end of the thread.
    let thread = runner.isOnDevice ? Self.trailingHistory(history, budget: 600) : history
    var opening = trimmed
    if !thread.isEmpty {
      opening = "これまでの会話:\n\(thread)\n\n今回の依頼:\n\(trimmed)"
    }
    // What the agent knows about the person, smaller on the device's window.
    let personal = personalContext(for: trimmed, budget: runner.isOnDevice ? 500 : 3_000)
    if !personal.isEmpty {
      opening = personal + "\n\n" + opening
    }

    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      let result: AIAnswerResult
      switch runner {
      case .cloud(let session):
        // Connected apps' tools join the agent's own for this run.
        session.externalTools = await self.loadMCPToolsForAgent()
        session.addUserMessage(opening)
        result = await self.runAgent(session: session, messageID: placeholder.id, scope: scope)
      case .onDevice:
        if #available(iOS 26.0, *) {
          result = await self.runOnDeviceAgent(prompt: opening, messageID: placeholder.id, scope: scope)
        } else {
          result = .failure(.noEngine)
        }
      }

      guard self.aiChatRequestID == requestID else { return }
      defer {
        self.isAIChatResponding = false
        self.aiChatTask = nil
        self.aiChatRequestID = nil
      }
      guard !Task.isCancelled else { return }

      let details = AIAnswerDetails(
        scopeLabel: scope.scopeLabel,
        engineLabel: runner.isOnDevice ? "エージェント（端末内）" : "エージェント",
        modelLabel: runner.isOnDevice ? nil : llm.modelLabel,
        // The records the agent opened are what its answer rests on.
        sourceCount: self.agentMessage(placeholder.id)?.agentSteps.filter { $0.icon == AgentTool.readRecord.icon }.count ?? 0,
        generatedAt: .now
      )
      switch result {
      case .answer(let text):
        self.updateAgentMessage(placeholder.id) {
          $0.text = text
          $0.details = details
          $0.isThinking = false
        }
        self.saveAIExchange(
          question: trimmed,
          answer: text,
          scopeLabel: scope.scopeLabel,
          engineLabel: details.engineLabel,
          modelLabel: details.modelLabel
        )
      case .failure(let failure):
        guard failure != .cancelled else { return }
        self.updateAgentMessage(placeholder.id) {
          $0.text = failure.message
          $0.details = details
          $0.isThinking = false
        }
      }
    }
    return true
  }

  /// Settles the pending approval card. Declining tells the model the change
  /// was refused, so it does not quietly try again.
  func resolveAgentApproval(_ approved: Bool) {
    pendingAgentApproval = nil
    let continuation = agentApprovalContinuation
    agentApprovalContinuation = nil
    continuation?.resume(returning: approved)
  }

  /// Runs model turns and tools until the model answers without calling one.
  private func runAgent(session: CloudAgentSession, messageID: UUID, scope: AIChatScope) async -> AIAnswerResult {
    var lastText = ""
    for _ in 0..<Self.agentMaxTurns {
      guard !Task.isCancelled else { return .failure(.cancelled) }
      let turn: AgentTurn
      do {
        turn = try await session.next()
      } catch let failure as AIAnswerFailure {
        return .failure(failure)
      } catch {
        return .failure(.server)
      }
      guard !Task.isCancelled else { return .failure(.cancelled) }

      if !turn.text.isEmpty {
        lastText = turn.text
      }
      guard !turn.toolCalls.isEmpty else {
        return lastText.isEmpty ? .failure(.empty) : .answer(lastText)
      }

      var results: [(call: AgentToolCall, outcome: AgentToolOutcome)] = []
      for call in turn.toolCalls {
        let outcome = await performAgentTool(call, messageID: messageID, scope: scope)
        results.append((call, outcome))
        guard !Task.isCancelled else { return .failure(.cancelled) }
      }
      session.addToolResults(results)
    }
    // Stopped at the limit: report what was done rather than nothing.
    let note = "作業が長くなったため、ここで止めました。続ける場合は「続けて」と送ってください。"
    return .answer(lastText.isEmpty ? note : lastText + "\n\n" + note)
  }

  /// Apple's model, when this device has it ready. It needs no key, so the
  /// agent works for someone who has not set up a cloud model.
  static var isOnDeviceAgentAvailable: Bool {
    if #available(iOS 26.0, *) {
      return SystemLanguageModel.default.isAvailable
    }
    return false
  }

  /// Runs the agent on the on-device model. The session calls the tools itself;
  /// each call goes through the same code as the cloud agent, in compact form.
  @available(iOS 26.0, *)
  private func runOnDeviceAgent(prompt: String, messageID: UUID, scope: AIChatScope) async -> AIAnswerResult {
    let tools = OnDeviceAgentTool.all(AgentTool.offeredOnDevice) { [weak self] name, argumentsJSON in
      guard let self else { return "" }
      let arguments = argumentsJSON.data(using: .utf8)
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
      let call = AgentToolCall(id: UUID().uuidString, name: name, arguments: arguments)
      return await self.performAgentTool(call, messageID: messageID, scope: scope, compact: true).text
    }
    let session = LanguageModelSession(tools: tools, instructions: Self.onDeviceAgentInstructions(scope: scope))
    do {
      let response = try await session.respond(to: prompt)
      let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? .failure(.empty) : .answer(text)
    } catch {
      return .failure(Task.isCancelled ? .cancelled : FoundationModelFailure.reason(for: error))
    }
  }

  /// Shows the change on the reply and waits for the person to decide.
  func requestAgentApproval(_ approval: AgentApproval) async -> Bool {
    // Only one card at a time; an older one still showing counts as declined.
    resolveAgentApproval(false)
    return await withCheckedContinuation { continuation in
      agentApprovalContinuation = continuation
      pendingAgentApproval = approval
    }
  }

  func agentMessage(_ id: UUID) -> AIChatMessage? {
    aiMessages.first { $0.id == id }
  }

  func updateAgentMessage(_ id: UUID, _ change: (inout AIChatMessage) -> Void) {
    guard let index = aiMessages.firstIndex(where: { $0.id == id }) else { return }
    change(&aiMessages[index])
  }

  /// Adds a step to the reply and returns its id so it can be settled later.
  func beginAgentStep(_ step: AgentStep, on messageID: UUID) -> UUID {
    updateAgentMessage(messageID) { $0.agentSteps.append(step) }
    return step.id
  }

  func finishAgentStep(_ stepID: UUID, on messageID: UUID, state: AgentStep.State, detail: String? = nil) {
    updateAgentMessage(messageID) { message in
      guard let index = message.agentSteps.firstIndex(where: { $0.id == stepID }) else { return }
      message.agentSteps[index].state = state
      if let detail {
        message.agentSteps[index].detail = detail
      }
    }
  }

  /// Shorter than the cloud instructions: every word counts against the
  /// on-device model's small window.
  static func onDeviceAgentInstructions(scope: AIChatScope) -> String {
    let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    return """
    あなたは記録アプリ「Memora」のエージェントです。道具で記録を調べ、依頼された作業をします。
    記録にないことは作りません。まず search_records で探し、必要なら read_record で読みます。
    変更する道具は利用者の承認後に実行されます。拒否されたら繰り返しません。
    頼まれた作業は質問で返さず、道具を呼んで行います。メールは宛先が不明でも draft_email で下書きを開きます。
    最後に、したことを日本語で短く伝えます。idは利用者に見せません。今日は\(today)。対象: \(scope.scopeLabel)。
    """
  }

  static func agentInstructions(scope: AIChatScope) -> String {
    let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    return """
    あなたは記録アプリ「Memora」のエージェントです。利用者の会議の記録・ジャーナル・タスク・プロジェクトを道具で調べ、依頼された作業を行います。

    - 事実は道具で読んだ記録だけに基づきます。記録にない数字・発言・決定を作りません。分からないことは分からないと書きます。
    - 資料やスライドを作る前に、search_records で探し、read_record で中身を読みます。
    - 資料は create_document に、見出し・箇条書き・必要なら表を使ったMarkdownで書きます。
    - スライドは create_slides で作ります。1枚目は箇条書きなしの表紙にし、各スライドの要点は3〜6個、短い言葉にします。
    - 担当者と期限は、記録で明言されたときだけ設定します。
    - 会議のあとの作業（フォローアップメールの下書き、次回の予定登録、Notionへの保存）も、依頼されたら道具で行います。メールは draft_email で下書きを開くだけで、送信は利用者がします。
    - 変更を伴う道具は、利用者が承認したときだけ実行されます。拒否されたら同じ操作を繰り返しません。
    - 利用者について覚えていることが渡されたら、それを前提に答えます。利用者が自分の役割・好み・関係者などを今後も使える形で伝えたときは、save_memory で覚えることを提案します。推測したことは覚えません。
    - Gmailがつながっていれば、search_email と read_email でメールを読めます。メールの内容は会議の記録と区別して伝えます。
    - mcp_ で始まる道具は、利用者が連携した外部アプリ（説明の [ ] 内）の道具です。依頼に合うときに使います。
    - 最後に、何を調べて何をしたかを日本語で短くまとめます。作った資料の本文を回答に繰り返しません。記録やプロジェクトのidは利用者に見せません。

    今日の日付: \(today)
    対象範囲: \(scope.scopeLabel)
    """
  }
}
