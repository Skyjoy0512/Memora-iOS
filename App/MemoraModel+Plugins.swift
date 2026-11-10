import Foundation

extension MemoraModel {
  /// Both the attachment service list and mentions read the same catalog and live grants.
  func integrationState(_ service: IntegrationCatalog) -> AIPlugin.Connection {
    guard service.isImplemented else { return .unavailable("このサービスの認証済みバックエンドは未接続です。現在利用できません。") }
    if service.id == "gmail", !GmailService.isConfigured {
      return .unavailable("このビルドにはGoogleのOAuthクライアントIDが設定されていません。")
    }
    guard integrationIsEnabled(service.id) else { return .setup("Ask AIでの利用が無効です。連携設定で有効にしてください。") }
    switch service.id {
    case "gmail":
      if GmailService.shared.isConnected { return .ready }
      return .setup("Gmailの読み取り連携を設定してください。")
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
    let availableToolNames = Set(registry.tools.values.filter { $0.isAvailable && $0.isEnabled }.map(\.name))
    let onDeviceTools = AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud ? nil : Set(AgentTool.onDeviceTools.map(\.rawValue))
    for skill in skillCatalog {
      let reason = skill.unavailabilityReason(enabled: !disabledSkillIDs.contains(skill.id), availableTools: availableToolNames, onDeviceTools: onDeviceTools)
      entries.append(AIPlugin(id: "skill:" + skill.id, name: skill.name, summary: skill.summary, aliases: skill.keywords,
        kind: .skill, state: reason.map(AIPlugin.Connection.setup) ?? .ready,
        toolIDs: Set(skill.toolNames.map { "memora:" + $0 }), permissions: ["記録のプライバシー設定と変更前の承認を維持します。"], cost: .unknown, provider: .memora, iconIdentifier: skill.iconIdentifier))
    }
    for tool in [AgentTool.searchRecords, .searchWeb, .deepResearch] {
      let id = "memora:" + tool.rawValue
      let available = registry.tools[id].map { $0.isAvailable && $0.isEnabled } == true
      entries.append(AIPlugin(id: "tool:" + id, name: tool == .searchRecords ? "ファイル・記録の検索" : (tool == .searchWeb ? "Web検索" : "Deep Research"),
        summary: tool.summary, aliases: tool == .searchRecords ? ["file", "record", "検索"] : ["web", "ウェブ", "リサーチ"],
        kind: available ? .builtin : .unavailable, state: available ? .ready : .unavailable("設定のWeb検索で利用者自身のBrave APIキーを登録してください。"),
        toolIDs: [id], permissions: [tool == .searchRecords ? "記録のプライバシー設定を適用します。" : "検索語と料金を実行前に確認します。"], cost: tool == .searchRecords ? .local : .paid, provider: .memora))
    }
    for template in companyTemplates where template.workspaceID == currentTeamID {
      let modelSupportsTemplate = onDeviceTools == nil || template.format == .docx
      let canAppend = template.format == .pptx && CompanyPresentationExporter.canAppend(template.analysis)
      let ready = (template.analysis.isAvailable || canAppend) && ProjectSourceFiles.resolve(template.fileReference).map { FileManager.default.fileExists(atPath: $0.path) } == true
      entries.append(AIPlugin(id: "template:" + template.id.uuidString, name: template.name,
        summary: "差し込み項目名と追加対応可否をAIへ渡します。書式ファイルは端末内で適用します。", aliases: ["会社", template.format.rawValue],
        kind: .template, state: ready && !modelSupportsTemplate ? .setup("PowerPointテンプレートの@利用にはツール対応クラウドAIが必要です。書式は端末内で適用します。") : ready ? .ready : .unavailable("対応する差し込み欄・空白レイアウト候補または原本がありません。資料の会社テンプレートから確認してください。"),
        toolIDs: [template.format == .docx ? "memora:create_document" : "memora:create_slides"], permissions: ["差し込み項目名と追加対応可否のみAIへ送信。生成前に承認。"], cost: .unknown, provider: .memora, templateID: template.id))
    }
    for server in mcpServers {
      let tools = registry.tools.values.filter { $0.requiredPermissions == ["mcp:" + server.id.uuidString] }
      let ready = server.isEnabled && integrationIsEnabled("mcp") && server.reviewedEndpoint == server.url
        && !tools.isEmpty && tools.allSatisfy { $0.isAvailable && $0.isEnabled }
      entries.append(AIPlugin(id: "mcp:" + server.id.uuidString, name: server.name, summary: "登録済みMCPサーバー", aliases: tools.flatMap { [$0.name, $0.summary] },
        kind: ready ? .connected : .connectable, state: ready ? .ready : .setup("MCP設定で接続先・認証・ツール・料金を確認してください。"),
        toolIDs: Set(tools.map(\.id)), permissions: ["mcp:" + server.id.uuidString], cost: server.hasUsageCharges.map { $0 ? .paid : .verifiedFree } ?? .unknown, provider: .mcp, serviceID: "mcp"))
    }
    return entries.map { entry in
      var entry = entry
      if entry.state.isReady, let onDeviceTools,
         !entry.toolIDs.isSubset(of: Set(onDeviceTools.map { "memora:" + $0 })) {
        entry.state = .setup("この指定にはツール対応のクラウドAI（BYOK）が必要です。AI整理で選んでください。")
      }
      return entry
    }
  }

  func mentionCandidates(query: String, scope: AIQueryScope = .global) -> [AIPlugin] {
    if case .space(let projectID) = scope {
      return projectMentionCandidates(query: query, projectID: projectID)
    }
    var candidates = pluginCatalog().filter { $0.matches(query) }
    // Files stay local until sending, when the usual RecordAccessPolicy applies.
    let files = meetings.filter { query.isEmpty || $0.title.localizedStandardContains(query) }.prefix(20)
    candidates += files.map { record in
      AIPlugin(id: "record:" + record.id.uuidString, name: record.title, summary: record.createdAt.formatted(date: .abbreviated, time: .omitted), aliases: [],
        kind: .file, state: .ready, toolIDs: ["memora:read_record"], permissions: ["記録の送信許可を確認します。"], cost: .local, provider: .memora, recordID: record.id)
    }
    return candidates
  }

  func pluginInfo(for mention: ComposerMention) -> AIPlugin {
    if let plugin = pluginCatalog().first(where: { $0.id == mention.pluginID }) { return plugin }
    if mention.pluginID.hasPrefix("record:"), let id = UUID(uuidString: String(mention.pluginID.dropFirst(7))), let record = meeting(id: id) {
      return AIPlugin(id: mention.pluginID, name: record.displayTitle, summary: "指定した記録。送信時に現在の許可を確認します。", aliases: [],
        kind: .file, state: .ready, toolIDs: ["memora:read_record"], permissions: ["記録の送信許可を適用します。"], cost: .local, provider: .memora, recordID: id)
    }
    if mention.pluginID.hasPrefix("source:"), let id = UUID(uuidString: String(mention.pluginID.dropFirst(7))), let source = source(id: id) {
      return projectSourcePlugin(source)
    }
    return AIPlugin(id: mention.pluginID, name: mention.label, summary: "選択した対象を確認できません。@から選び直してください。", aliases: [],
      kind: .unavailable, state: .unavailable("削除済みまたは利用できない対象です。"), toolIDs: [], permissions: [], cost: .unknown, provider: .memora)
  }

  func updateComposerMentions(from old: String, to new: String) {
    composerMentions = ComposerMention.reconciled(composerMentions, from: old, to: new)
  }

  func saveComposerMentions() {
    guard !isStoreProtected, composerDraftFailure == nil else { return }
    guard !composerMentions.isEmpty, let data = try? JSONEncoder().encode(composerMentions) else {
      DraftStore.clear("composer.mentions"); return
    }
    DraftStore.save(String(decoding: data, as: UTF8.self), key: "composer.mentions")
  }
}
