import Foundation

extension MemoraModel {
  @discardableResult
  func sendPluginChat(_ question: String, pluginIDs: [String], attachment: AIAttachment?, preparedAttachment: PreparedAIAttachment? = nil) -> Bool {
    guard !isAIChatResponding else { return false }
    func refuse(_ reason: String) -> Bool {
      if attachment != nil { aiRequestRefusalMessage = reason; return false }
      var user = AIChatMessage(role: .user, text: question)
      user.pluginIDs = pluginIDs
      aiMessages.append(user)
      aiMessages.append(AIChatMessage(role: .assistant, text: reason))
      return true
    }
    if let attachment {
      guard let preparedAttachment, AgentAttachmentContext.content(attachment: attachment, prepared: preparedAttachment) != nil else {
        return refuse(preparedAttachment?.failure ?? "添付を解析してから送信してください。入力と添付は保持しています。")
      }
    }
    var plugins: [AIPlugin] = []
    let catalog = pluginCatalog()
    for id in Set(pluginIDs).sorted() {
      if let plugin = catalog.first(where: { $0.id == id }) {
        guard plugin.state.isReady else { return refuse(plugin.state.reason ?? "連携設定を確認してください。") }
        plugins.append(plugin)
      } else if id.hasPrefix("record:"), let uuid = UUID(uuidString: String(id.dropFirst(7))), let record = meeting(id: uuid) {
        if AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud,
           !RecordAccessPolicy.allows(record.effectivePrivacy, purpose: .cloudAI) {
          return refuse("「\(record.displayTitle)」は外部AIへの送信が許可されていません。記録のプライバシー設定を確認するか、端末内AIを選んでください。記録は送信していません。")
        }
        plugins.append(AIPlugin(id: id, name: record.displayTitle, summary: "指定した記録", aliases: [], kind: .file, state: .ready,
          toolIDs: ["memora:read_record"], permissions: [], cost: .local, provider: .memora, recordID: uuid))
      } else { return refuse("指定したプラグインまたは記録は削除されています。@から選び直してください。") }
    }
    guard plugins.filter({ $0.id.hasPrefix("skill:") }).count <= 2 else { return refuse("1つの依頼で組み合わせるスキルは2つまでです。必要な手順を選び直してください。") }
    let configuration = askAIConfiguration
    guard !configuration.llm.isMemoraIntelligence else {
      return refuse("プラグインは端末内AIまたは利用者自身のキーを登録したクラウドAIで利用してください。設定の「AI整理」で切り替えられます。")
    }
    if AIEngineService.effectiveEngine(configuration.engine) == .cloud, !configuration.llm.supportsToolCalling {
      return refuse("このモデルのツール呼び出しはオフです。設定の「AI整理」でツール対応モデルを選び、有効にしてください。")
    }
    let onDevice = AIEngineService.effectiveEngine(configuration.engine) != .cloud
    if onDevice, attachment != nil { return refuse("添付とプラグインの併用にはツール対応のクラウドAI（BYOK）が必要です。入力と添付は保持しています。") }
    if onDevice, plugins.contains(where: { $0.provider == .mcp || !($0.toolIDs.isSubset(of: Set(AgentTool.onDeviceTools.map { "memora:" + $0.rawValue }))) }) {
      return refuse("この指定にはツール対応のクラウドAI（BYOK）が必要です。設定の「AI整理」で登録済みモデルを選んでください。外部サービスは実行していません。")
    }
    let policy = AIPluginExecutionPolicy.forSelection(pluginIDs: pluginIDs, plugins: plugins, onDevice: onDevice)
    return sendAgentChat(question, attachment: attachment, pluginPolicy: policy, preparedAttachment: preparedAttachment)
  }

  func pluginCallIsPermitted(_ call: AgentToolCall, messageID: UUID) -> Bool {
    guard let policy = agentPluginPolicies[messageID] else { return true }
    let catalog = pluginCatalog()
    guard policy.pluginIDs.allSatisfy({ id in
      if id.hasPrefix("person:") { return policy.personID != nil }
      if id.hasPrefix("record:"), let recordID = UUID(uuidString: String(id.dropFirst(7))) { return meeting(id: recordID) != nil }
      return catalog.first(where: { $0.id == id })?.state.isReady == true
    }) else { return false }
    return policy.permits(call.name, arguments: call.arguments)
  }

  func directPluginReadRefusal(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome? {
    guard !agentBlockedExternalTools[messageID, default: []].contains(call.name) else {
      return AgentToolOutcome(text: "この依頼ではメール取得を再実行しません。", isError: true)
    }
    let account = GmailService.shared.connectedEmail
    let revision = GmailService.shared.connectionRevision
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .envelopeOpen,
      title: "Gmailで\(call.tool == .searchEmail ? "メールを検索" : "メールを閲覧")",
      lines: [account.map { "アカウント: " + $0 } ?? "アカウント名を取得できていません。Gmailの接続設定を確認してください。", "取得したメールは選択中のAIへ送られます。", "外部処理の料金は未確認です。今回の操作だけを許可します。", String(decoding: (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])) ?? Data(), as: UTF8.self)],
      confirmTitle: "実行"), changesData: false)
    guard approved else {
      agentBlockedExternalTools[messageID, default: []].formUnion(["search_email", "read_email"])
      return AgentToolOutcome(text: "利用者が外部メールの取得を承認しませんでした。取得せず、同じ操作を再要求しません。")
    }
    guard !Task.isCancelled else { return AgentToolOutcome(text: "メール取得を停止しました。", isError: true) }
    guard revision == GmailService.shared.connectionRevision,
          account == GmailService.shared.connectedEmail, integrationIsEnabled("gmail"), GmailService.shared.isConnected,
          toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID]) else {
      agentBlockedExternalTools[messageID, default: []].formUnion(["search_email", "read_email"])
      return AgentToolOutcome(text: "接続先アカウントまたは権限が変わったため、メールを取得していません。連携設定を確認してください。", isError: true)
    }
    return nil
  }
}
