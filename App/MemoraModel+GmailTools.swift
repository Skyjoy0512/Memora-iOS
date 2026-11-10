import Foundation

extension MemoraModel {
  func gmailReadTool(_ call: AgentToolCall, messageID: UUID, compact: Bool,
                     service: GmailService) async -> AgentToolOutcome {
    guard !agentBlockedExternalTools[messageID, default: []].contains(call.name),
          let context = GmailAgentReadContext(in: self, call: call, messageID: messageID, compact: compact, service: service) else {
      return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true)
    }
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .envelopeOpen,
      title: "Gmailで\(call.tool == .searchEmail ? "メールを検索" : "メールを閲覧")",
      lines: [service.connectedEmail.map { "アカウント: " + $0 } ?? "アカウント名を取得できていません。Gmailの接続設定を確認してください。", "取得したメールは選択中のAIへ送られます。", "外部処理の料金は未確認です。今回の操作だけを許可します。", String(decoding: (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])) ?? Data(), as: UTF8.self)],
      confirmTitle: "実行"))
    guard context.isCurrent(in: self) else {
      return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true)
    }
    guard approved else {
      agentBlockedExternalTools[messageID, default: []].formUnion(["search_email", "read_email"])
      return AgentToolOutcome(text: "利用者が外部メールの取得を承認しませんでした。取得せず、同じ操作を再要求しません。")
    }
    let current: @MainActor @Sendable () -> Bool = { [weak self] in
      guard let self else { return false }
      return context.isCurrent(in: self)
    }
    let search = call.tool == .searchEmail
    let query = call.string("query")
    let stepID = beginAgentStep(AgentStep(icon: search ? AgentTool.searchEmail.icon : AgentTool.readEmail.icon,
      title: search ? (query.isEmpty ? "受信トレイを確認" : "メールを検索") : "メールを読む",
      query: search && !query.isEmpty ? query : nil), on: messageID)
    do {
      let messages: [GmailMessage]
      if search {
        messages = try await service.search(query, limit: min(call.int("limit") ?? 8, compact ? 5 : 15), isAuthorized: current)
      } else {
        messages = [try await service.read(call.string("id"), isAuthorized: current)]
      }
      guard current(), retainGmailResultAuthorization(context, messageID: messageID) else {
        throw ExternalToolFailure.permissionDenied
      }
      finishAgentStep(stepID, on: messageID, state: .done,
        detail: search ? "\(messages.count)件" : messages.first?.subject,
        results: search ? messages.map { AgentStep.Result(title: $0.subject, subtitle: $0.from) } : [])
      if search {
        guard !messages.isEmpty else { return AgentToolOutcome(text: "該当するメールはありません。") }
        return AgentToolOutcome(text: messages.map { message in
          let date = message.date.map(Self.agentDate) ?? ""
          return "- id=\(message.id) \(date) 差出人: \(message.from) 件名: \(message.subject) 冒頭: \(message.snippet.prefix(compact ? 60 : 160))"
        }.joined(separator: "\n"))
      }
      guard let message = messages.first else { throw ExternalToolFailure.failed }
      let body = message.body.isEmpty ? message.snippet : message.body
      return AgentToolOutcome(text: """
      差出人: \(message.from)
      宛先: \(message.to)
      件名: \(message.subject)
      日時: \(message.date.map(Self.agentDate) ?? "不明")

      \(body.prefix(compact ? 1_500 : 12_000))
      """)
    } catch {
      if context.ownsMessage(in: self) {
        finishAgentStep(stepID, on: messageID, state: .failed, detail: "読み込めませんでした")
        agentBlockedExternalTools[messageID, default: []].formUnion(["search_email", "read_email"])
      }
      guard current() else { return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true) }
      return AgentToolOutcome(text: ExternalToolFailure.message(for: error), isError: true)
    }
  }
}
