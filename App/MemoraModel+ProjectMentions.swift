import Foundation

extension MemoraModel {
  func projectMentionCandidates(query: String, projectID: UUID) -> [AIPlugin] {
    guard currentTeamID == nil, space(id: projectID) != nil else { return [] }
    var candidates = projectReadingPlugins().filter { $0.matches(query) }
    let cloud = AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud
    candidates += meetings.filter { $0.spaceID == projectID && (query.isEmpty || $0.displayTitle.localizedStandardContains(query)) }
      .prefix(20).map { record in
        AIPlugin(id: "record:" + record.id.uuidString, name: record.displayTitle, summary: "このプロジェクトの記録", aliases: [], kind: .file,
          state: projectEvidenceAllowed(.meeting(record.id), projectID: projectID, cloud: cloud) ? .ready : .unavailable("この記録の送信許可を確認してください。"),
          toolIDs: ["memora:read_record"], permissions: ["所属と送信許可を実行時に再確認します。"], cost: .local, provider: .memora, recordID: record.id)
      }
    candidates += projectSources.filter { $0.projectID == projectID && (query.isEmpty || $0.title.localizedStandardContains(query)) }
      .prefix(20).map(projectSourcePlugin)
    return candidates
  }

  func projectSourcePlugin(_ source: ProjectSource) -> AIPlugin {
    let cloud = AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud
    let ready = source.projectID.map { projectEvidenceAllowed(.source(source.id), projectID: $0, cloud: cloud) } == true
    return AIPlugin(id: "source:" + source.id.uuidString, name: source.title,
      summary: source.kindLabel + " · " + source.statusLabel, aliases: [], kind: .file,
      state: ready ? .ready : .unavailable("本文の解析状態と外部AIへの送信許可をソース詳細で確認してください。"),
      toolIDs: ["memora:read_record"], permissions: ["現在の所属・本文・送信許可を確認します。"], cost: .local,
      provider: .memora, sourceID: source.id)
  }

  private func projectReadingPlugins() -> [AIPlugin] {
    let allowed = Set(ProjectMentionSelection.readingTools.map { "memora:" + $0 })
    var entries = pluginCatalog().map { plugin in
      var plugin = plugin
      let skill = skillCatalog.first { "skill:" + $0.id == plugin.id }
      let scoped = skill.map { ($0.scopes ?? [.global]).contains(.project) } ?? (plugin.kind == .builtin)
      if !scoped || plugin.toolIDs.isEmpty || !plugin.toolIDs.isSubset(of: allowed) {
        plugin.state = .unavailable("プロジェクト内は資料の読み取り専用です。この連携・変更操作は全体のAsk AIで利用してください。")
        plugin.kind = .unavailable
      }
      return plugin
    }
    let registry = toolRegistry()
    for tool in [AgentTool.readRecord, .listTasks] {
      let id = "memora:" + tool.rawValue
      let enabled = registry.tools[id].map { $0.isAvailable && $0.isEnabled } == true
      entries.append(AIPlugin(id: "tool:" + id, name: tool == .readRecord ? "資料の本文を読む" : "プロジェクトのタスクを確認",
        summary: "このプロジェクトの許可された情報だけを読みます。", aliases: [tool.rawValue], kind: .builtin,
        state: enabled ? .ready : .setup("ツール設定で有効にしてください。"), toolIDs: [id], permissions: ["読み取り専用"], cost: .local, provider: .memora))
    }
    return entries
  }

  func projectMentionSelection(_ ids: [String], projectID: UUID) -> ProjectMentionSelection? {
    guard currentTeamID == nil, space(id: projectID) != nil else { return nil }
    let ids = Array(Set(ids)).sorted()
    let cloud = AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud
    let catalog = projectReadingPlugins()
    var tools: Set<String> = []
    var targets: Set<ProjectCitation.Target> = []
    var skills: [MemoraSkill] = []
    var searchesProject = false
    for id in ids {
      if id.hasPrefix("record:"), let uuid = UUID(uuidString: String(id.dropFirst(7))) {
        let target = ProjectCitation.Target.meeting(uuid)
        guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud) else { return nil }
        targets.insert(target); tools.insert("read_record")
      } else if id.hasPrefix("source:"), let uuid = UUID(uuidString: String(id.dropFirst(7))) {
        let target = ProjectCitation.Target.source(uuid)
        guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud) else { return nil }
        targets.insert(target); tools.insert("read_record")
      } else {
        guard let plugin = catalog.first(where: { $0.id == id }), plugin.state.isReady else { return nil }
        tools.formUnion(plugin.toolIDs.map { String($0.dropFirst("memora:".count)) })
        searchesProject = true
        if let skill = skillCatalog.first(where: { "skill:" + $0.id == id }) { skills.append(skill) }
      }
    }
    guard skills.count <= 2, tools.isSubset(of: ProjectMentionSelection.readingTools) else { return nil }
    if ids.isEmpty { tools = ProjectMentionSelection.readingTools }
    if !ids.isEmpty, targets.isEmpty, tools == ["list_tasks"] {
      targets = Set(tasks.filter { task in
        task.meetingID.flatMap { meeting(id: $0)?.spaceID } == projectID
          && projectEvidenceAllowed(.task(task.id), projectID: projectID, cloud: cloud)
      }.map { .task($0.id) })
      searchesProject = false
    }
    return ProjectMentionSelection(pluginIDs: ids, toolNames: tools,
      targets: ids.isEmpty || (targets.isEmpty && searchesProject) ? nil : targets,
      guidance: MemoraSkill.guidance(skills, budget: 1_600))
  }
}
