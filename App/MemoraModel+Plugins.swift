import Foundation

extension MemoraModel {
  /// Both the attachment service list and mentions read the same catalog and live grants.
  func integrationState(_ service: IntegrationCatalog) -> AIPlugin.Connection {
    guard service.isImplemented else { return .unavailable("このサービスの認証済みバックエンドは未接続です。現在利用できません。") }
    guard integrationIsEnabled(service.id) else { return .setup("Ask AIでの利用が無効です。連携設定で有効にしてください。") }
    switch service.id {
    case "gmail":
      if GmailService.shared.isConnected { return .ready }
      return GmailService.isConfigured ? .setup("Gmailの読み取り連携を設定してください。") : .unavailable("このビルドにはGoogleのOAuthクライアントIDが設定されていません。")
    case "notion": return NotionService.isConfigured ? .ready : .setup("Notionのトークンと保存先ページを設定してください。検索・閲覧は未対応です。")
    case "calendar": return CalendarService.access == .granted ? .ready : .setup("端末のカレンダーへのアクセスを許可してください。")
    case "mcp": return .setup("登録・接続確認・ツールと料金の確認を行ってください。")
    default: return .unavailable("現在利用できません。")
    }
  }

  private func isConnectable(_ state: AIPlugin.Connection) -> Bool {
    if case .setup = state { return true }
    return false
  }

  func pluginCatalog() -> [AIPlugin] {
    let registry = toolRegistry()
    var entries = IntegrationCatalog.services.map { service in
      let state = integrationState(service)
      return AIPlugin(id: "service:" + service.id, name: service.name, summary: service.summary, aliases: service.aliases,
        kind: state.isReady ? .connected : (isConnectable(state) ? .connectable : .unavailable),
        state: state, toolIDs: Set(service.toolNames.map { "memora:" + $0 }), permissions: [service.permissions],
        cost: service.id == "calendar" ? .local : .unknown, provider: service.id == "mcp" ? .mcp : (service.isImplemented ? .directAPI : .composio), serviceID: service.id)
    }
    for skill in MemoraSkill.bundled {
      let enabled = !disabledSkillIDs.contains(skill.id)
      entries.append(AIPlugin(id: "skill:" + skill.id, name: skill.name, summary: skill.summary, aliases: skill.keywords,
        kind: enabled ? .builtin : .unavailable, state: enabled ? .ready : .setup("スキル設定で有効にしてください。"),
        toolIDs: Set(skill.toolNames.map { "memora:" + $0 }), permissions: ["記録のプライバシー設定と変更前の承認を維持します。"], cost: .local, provider: .memora))
    }
    for tool in [AgentTool.searchRecords, .searchWeb, .deepResearch] {
      let id = "memora:" + tool.rawValue
      let available = registry.tools[id]?.isAvailable == true
      entries.append(AIPlugin(id: "tool:" + id, name: tool == .searchRecords ? "ファイル・記録の検索" : (tool == .searchWeb ? "Web検索" : "Deep Research"),
        summary: tool.summary, aliases: tool == .searchRecords ? ["file", "record", "検索"] : ["web", "ウェブ", "リサーチ"],
        kind: available ? .builtin : .unavailable, state: available ? .ready : .unavailable("設定のWeb検索で利用者自身のBrave APIキーを登録してください。"),
        toolIDs: [id], permissions: [tool == .searchRecords ? "記録のプライバシー設定を適用します。" : "検索語と料金を実行前に確認します。"], cost: tool == .searchRecords ? .local : .paid, provider: .memora))
    }
    for server in mcpServers {
      let ready = server.isEnabled && integrationIsEnabled("mcp") && server.reviewedEndpoint == server.url
      let tools = registry.tools.values.filter { $0.requiredPermissions == ["mcp:" + server.id.uuidString] }
      entries.append(AIPlugin(id: "mcp:" + server.id.uuidString, name: server.name, summary: "登録済みMCPサーバー", aliases: tools.flatMap { [$0.name, $0.summary] },
        kind: ready ? .connected : .connectable, state: ready ? .ready : .setup("MCP設定で接続先・認証・ツール・料金を確認してください。"),
        toolIDs: Set(tools.map(\.id)), permissions: ["mcp:" + server.id.uuidString], cost: server.hasUsageCharges.map { $0 ? .paid : .verifiedFree } ?? .unknown, provider: .mcp, serviceID: "mcp"))
    }
    return entries
  }

  func mentionCandidates(query: String) -> [AIPlugin] {
    var candidates = pluginCatalog().filter { $0.matches(query) }
    // Files stay local until sending, when the usual RecordAccessPolicy applies.
    let files = meetings.filter { query.isEmpty || $0.title.localizedStandardContains(query) }.prefix(20)
    candidates += files.map { record in
      AIPlugin(id: "record:" + record.id.uuidString, name: record.title, summary: record.createdAt.formatted(date: .abbreviated, time: .omitted), aliases: [],
        kind: .file, state: .ready, toolIDs: ["memora:read_record"], permissions: ["記録の送信許可を確認します。"], cost: .local, provider: .memora, recordID: record.id)
    }
    return candidates
  }

  func updateComposerMentions(from old: String, to new: String) {
    composerMentions = ComposerMention.reconciled(composerMentions, from: old, to: new)
  }

  func saveComposerMentions() {
    guard !isStoreProtected else { return }
    guard !composerMentions.isEmpty, let data = try? JSONEncoder().encode(composerMentions) else {
      DraftStore.clear("composer.mentions"); return
    }
    DraftStore.save(String(decoding: data, as: UTF8.self), key: "composer.mentions")
  }
}
