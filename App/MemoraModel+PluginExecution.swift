import Foundation

extension MemoraModel {
  @discardableResult
  func sendPluginChat(_ question: String, pluginIDs: [String], attachment: AIAttachment?) -> Bool {
    guard !isAIChatResponding else { return false }
    func refuse(_ reason: String) -> Bool {
      var user = AIChatMessage(role: .user, text: question)
      user.pluginIDs = pluginIDs
      aiMessages.append(user)
      aiMessages.append(AIChatMessage(role: .assistant, text: reason))
      return true
    }
    guard attachment == nil else {
      return refuse("プラグインのエージェントは添付をまだ読めません。添付を外すか、プラグイン指定を外して通常の質問で確認してください。添付は外部サービスへ送っていません。")
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
    let configuration = askAIConfiguration
    guard !configuration.llm.isMemoraIntelligence else {
      return refuse("プラグインは端末内AIまたは利用者自身のキーを登録したクラウドAIで利用してください。設定の「AI整理」で切り替えられます。")
    }
    if AIEngineService.effectiveEngine(configuration.engine) == .cloud, !configuration.llm.supportsToolCalling {
      return refuse("このモデルのツール呼び出しはオフです。設定の「AI整理」でツール対応モデルを選び、有効にしてください。")
    }
    let onDevice = AIEngineService.effectiveEngine(configuration.engine) != .cloud
    if onDevice, plugins.contains(where: { $0.provider == .mcp || !($0.toolIDs.isSubset(of: Set(AgentTool.onDeviceTools.map { "memora:" + $0.rawValue }))) }) {
      return refuse("この指定にはツール対応のクラウドAI（BYOK）が必要です。設定の「AI整理」で登録済みモデルを選んでください。外部サービスは実行していません。")
    }
    var ids = plugins.reduce(into: Set<String>()) { $0.formUnion($1.toolIDs) }
    if !onDevice { ids.insert("memora:ask_user") }
    let policy = AIPluginExecutionPolicy(pluginIDs: pluginIDs, toolIDs: ids,
      recordIDs: Set(plugins.compactMap(\.recordID)), limitsRecordReads: !plugins.contains { $0.kind == .builtin || $0.id == "service:notion" })
    return sendAgentChat(question, pluginPolicy: policy)
  }

  func pluginCallIsPermitted(_ call: AgentToolCall, messageID: UUID) -> Bool {
    agentPluginPolicies[messageID]?.permits(call.name, arguments: call.arguments) ?? true
  }

  func approveDirectPluginRead(_ call: AgentToolCall, messageID: UUID) async -> Bool {
    guard !agentBlockedExternalTools[messageID, default: []].contains(call.name) else { return false }
    let account = GmailService.shared.connectedEmail
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: .envelopeOpen,
      title: "Gmailで\(call.tool == .searchEmail ? "メールを検索" : "メールを閲覧")",
      lines: ["取得したメールは選択中のAIへ送られます。", "外部処理の料金は未確認です。今回の操作だけを許可します。", String(decoding: (try? JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])) ?? Data(), as: UTF8.self)],
      confirmTitle: "実行"), changesData: false)
    if !approved { agentBlockedExternalTools[messageID, default: []].formUnion(["search_email", "read_email"]) }
    return approved && !Task.isCancelled && account == GmailService.shared.connectedEmail
      && integrationIsEnabled("gmail") && GmailService.shared.isConnected
      && toolRegistry().permits(call.name, arguments: call.arguments, policy: agentPluginPolicies[messageID])
  }
}
