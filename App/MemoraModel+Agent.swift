import Foundation

// The Ask AI agent: a cloud model that reads the records through tools and,
// once the person approves, makes documents, tasks, projects and memos.
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

    // Tools need a cloud model; the on-device one is not asked to pretend.
    guard AIEngineService.effectiveEngine(configuration.engine) == .cloud else {
      aiMessages.append(AIChatMessage(
        role: .assistant,
        text: "エージェントはクラウドのモデルで動きます。設定の「AI整理」でクラウド（BYOK）を選ぶか、入力欄のモデル選択で登録済みのモデルを選んでください。"
      ))
      return true
    }
    let llm = configuration.llm
    guard let session = CloudAgentSession(llm: llm, system: Self.agentInstructions(scope: scope)) else {
      aiMessages.append(AIChatMessage(role: .assistant, text: AIAnswerFailure.missingKey.message))
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

    var opening = trimmed
    if !history.isEmpty {
      opening = "これまでの会話:\n\(history)\n\n今回の依頼:\n\(trimmed)"
    }
    session.addUserMessage(opening)

    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      let result = await self.runAgent(session: session, messageID: placeholder.id, scope: scope)

      guard self.aiChatRequestID == requestID else { return }
      defer {
        self.isAIChatResponding = false
        self.aiChatTask = nil
        self.aiChatRequestID = nil
      }
      guard !Task.isCancelled else { return }

      let details = AIAnswerDetails(
        scopeLabel: scope.scopeLabel,
        engineLabel: "エージェント",
        modelLabel: llm.modelLabel,
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

  static func agentInstructions(scope: AIChatScope) -> String {
    let today = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    return """
    あなたは記録アプリ「Memora」のエージェントです。利用者の会議の記録・ジャーナル・タスク・プロジェクトを道具で調べ、依頼された作業を行います。

    - 事実は道具で読んだ記録だけに基づきます。記録にない数字・発言・決定を作りません。分からないことは分からないと書きます。
    - 資料やスライドを作る前に、search_records で探し、read_record で中身を読みます。
    - 資料は create_document に、見出し・箇条書き・必要なら表を使ったMarkdownで書きます。
    - スライドは create_slides で作ります。1枚目は箇条書きなしの表紙にし、各スライドの要点は3〜6個、短い言葉にします。
    - 担当者と期限は、記録で明言されたときだけ設定します。
    - 変更を伴う道具は、利用者が承認したときだけ実行されます。拒否されたら同じ操作を繰り返しません。
    - 最後に、何を調べて何をしたかを日本語で短くまとめます。作った資料の本文を回答に繰り返しません。

    今日の日付: \(today)
    対象範囲: \(scope.scopeLabel)
    """
  }
}
