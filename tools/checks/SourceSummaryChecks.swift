import Foundation
import SQLite3

@main struct SourceSummaryChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try await defaultsAndExplicitChoices(root)
    try await refusals(root)
    try await failuresAndAttribution(root)
    try await sqlFailure(root)
    for change in 0..<13 { try await race(root, change: change) }
    print("SourceSummaryChecks: PASS. Production source-summary admission/orchestration, adaptive and stored explicit choices, strict cloud privacy, stale/deleted model/template refusal, length constraints, original-summary attribution, retry/history, SQLite admission/final-write failure and13 suspended context/config races. SQLite and file reads are real; model state, registry and summarizer are fixtures, no network/model/device claim.")
  }

  @MainActor static func fixture(_ root: URL, _ label: String) async throws -> (MemoraModel, UUID) {
    let model = try MemoraModel(storeURL: root.appendingPathComponent(label + ".sqlite"))
    let reference = try await ProjectSourceFiles.shared.write(JSONEncoder().encode([
      ProjectSourceText(text: "実際の保存本文: 検証日と条件を保持する", page: 7, time: 42)
    ]), extension: "json")
    let source = ProjectSource(kind: .web, title: "原文資料", originalURL: URL(string: "https://example.org/article"),
      extractedTextReference: reference, processingStatus: .ready, textCoverage: .partial)
    precondition(model.storeProjectSource(source))
    return (model, source.id)
  }

  @MainActor static func defaultsAndExplicitChoices(_ root: URL) async throws {
    let articleHint = "記事の構成: 見出しと段落のまとまりを原文の順に整理する。"
    MeetingSummarizer.reset()
    let (model, id) = try await fixture(root, "default")
    model.summaryPreferences.method = .fixed
    model.summaryPreferences.length = .detailed
    await model.summarizeProjectSource(id)
    precondition(MeetingSummarizer.calls.count == 1)
    let call = MeetingSummarizer.calls[0]
    precondition(call.input.template == .adaptiveSource && call.input.preferences.length == .detailed)
    precondition(call.input.sourceContext?.contains(articleHint) == true)
    precondition(model.source(id: id)?.summaryModeID == SummaryMode.article.rawValue)
    precondition(call.engine == .foundation && call.llm.modelID == "ask-ai")
    precondition(call.input.transcript.first?.speaker == "ページ7" && call.input.transcript.first?.timestamp == 42)
    precondition(model.tasks.isEmpty && model.source(id: id)?.summaryStatus == .ready)
    await model.summarizeProjectSource(id)
    precondition(MeetingSummarizer.calls.count == 1)

    MeetingSummarizer.reset()
    let (explicit, explicitID) = try await fixture(root, "explicit")
    var source = explicit.source(id: explicitID)!
    source.privacy.classification = .general
    source.privacy.allowsCloudAI = true
    source.summary = "以前の要約"
    source.summaryTextReference = source.extractedTextReference
    source.summaryHistory = ["古い1", "古い2", "古い3"]
    precondition(explicit.storeProjectSource(source))
    let registeredID = UUID()
    explicit.registeredLLMs.models = [.init(id: registeredID, selection: .init(modelID: "chosen-model"))]
    let options = SourceSummaryOptions(templateID: SummaryTemplateChoice.builtIn(.meetingMinutes).id,
      length: .concise, engineChoice: .registered(registeredID))
    let admitted = explicit.startProjectSourceSummary(explicitID, options: options,
      expectedSource: source, configurationIdentity: explicit.summaryConfigurationIdentity)
    precondition(admitted && explicit.sourcePreparationJobs[explicitID] != nil)
    precondition(!explicit.startProjectSourceSummary(explicitID, options: options,
      expectedSource: explicit.source(id: explicitID)!, configurationIdentity: explicit.summaryConfigurationIdentity))
    let job = explicit.sourcePreparationJobs[explicitID]!.task
    await job.value
    precondition(MeetingSummarizer.calls.count == 1 && MeetingSummarizer.allowed == [true])
    precondition(MeetingSummarizer.calls[0].input.template == .builtIn(.meetingMinutes))
    precondition(MeetingSummarizer.calls[0].input.preferences.length == .concise)
    precondition(MeetingSummarizer.calls[0].engine == .cloud && MeetingSummarizer.calls[0].llm.modelID == "chosen-model")
    precondition(MeetingSummarizer.calls[0].input.sourceContext?.contains(articleHint) == false)
    precondition(explicit.source(id: explicitID)?.summaryModeID == SummaryMode.article.rawValue)
    precondition(explicit.source(id: explicitID)?.summaryOptions == options && explicit.tasks.isEmpty)
    precondition(explicit.source(id: explicitID)?.summaryHistory == ["古い2", "古い3", "以前の要約"])
    let saved = try reload(explicit).first!
    precondition(saved == explicit.source(id: explicitID) && saved.summaryOptions == options)
    precondition(saved.summaryModeID == SummaryMode.article.rawValue)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
    legacy.removeValue(forKey: "summaryOptions")
    legacy.removeValue(forKey: "summaryAttemptTextReference")
    legacy.removeValue(forKey: "summaryModeID")
    let old = try JSONDecoder().decode(ProjectSource.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.id == saved.id && old.extractedTextReference == saved.extractedTextReference)
    precondition(old.summaryOptions == nil && old.summaryAttemptTextReference == nil && old.summary == saved.summary)
    precondition(old.summaryModeID == nil)
    precondition(old.projectID == saved.projectID && old.kind == saved.kind && old.title == saved.title)
    precondition(old.originalURL == saved.originalURL && old.localFileReference == saved.localFileReference)
    precondition(old.textCoverage == saved.textCoverage && old.privacy == saved.privacy)
    precondition(old.summaryTextReference == saved.summaryTextReference && old.summaryStatus == saved.summaryStatus)
    precondition(old.summaryHistory == saved.summaryHistory && old.summaryKnowledge == saved.summaryKnowledge)
    MeetingSummarizer.outcome = .success(.init(markdown: "別の要約"))
    await explicit.summarizeProjectSource(explicitID, retry: true)
    precondition(MeetingSummarizer.calls.count == 2 && MeetingSummarizer.calls[1].llm.modelID == "chosen-model")
    precondition(explicit.sourcePreparationJobs.isEmpty && explicit.projectSourceProcessingIDs.isEmpty)
  }

  @MainActor static func refusals(_ root: URL) async throws {
    MeetingSummarizer.reset()
    let (model, id) = try await fixture(root, "refusals")
    model.askAIConfiguration = (.cloud, .init(modelID: "default-cloud"))
    let original = model.source(id: id)!
    precondition(model.sourceSummaryUnavailableReason(id: id, options: .init()) != nil)
    precondition(!model.startProjectSourceSummary(id, options: .init(), expectedSource: original,
      configurationIdentity: model.summaryConfigurationIdentity))
    await model.summarizeProjectSource(id)
    precondition(MeetingSummarizer.calls.isEmpty && model.source(id: id)?.summaryStatus == .unavailable)
    precondition(model.source(id: id)?.privacy == original.privacy)
    let local = SourceSummaryOptions(engineChoice: .onDevice)
    precondition(model.sourceSummaryUnavailableReason(id: id, options: local) == nil)
    precondition(model.sourceSummaryConfiguration(for: .init(engineChoice: .settings))?.llm.modelID == "settings")
    precondition(model.sourceSummaryConfiguration(for: .init(engineChoice: .registered(UUID()))) == nil)
    precondition(model.sourceSummaryTemplate(for: .init(templateID: "removed-template")) == nil)
    precondition(model.sourceSummaryUnavailableReason(id: id, options: .init(templateID: "removed-template")) != nil)
    precondition(model.sourceSummaryUnavailableReason(id: id, options: .init(templateID: String(repeating: "x", count: 513))) != nil)
    var limited = SummaryMarketTemplate(id: "limited", title: "限定", detail: "", symbol: .docText, lead: "限定")
    limited.supportedSummaryLengths = [.concise]
    model.choices.append(.market(limited))
    precondition(model.sourceSummaryUnavailableReason(id: id,
      options: .init(templateID: limited.id, length: .detailed, engineChoice: .onDevice)) != nil)
    precondition(model.sourceSummaryUnavailableReason(id: id,
      options: .init(templateID: limited.id, length: .concise, engineChoice: .onDevice)) == nil)
    for condition in 0..<5 {
      model.isRestoring = condition == 0
      model.isStoreProtected = condition == 1
      model.currentTeamID = condition == 2 ? "team" : nil
      model.projectSourceProcessingIDs = condition == 3 ? [id] : []
      if condition == 4 { model.projectSources[0].extractedTextReference = nil }
      precondition(model.sourceSummaryUnavailableReason(id: id, options: local) != nil)
    }
    precondition(MeetingSummarizer.calls.isEmpty)

    let (admission, admissionID) = try await fixture(root, "stale-admission")
    let expected = admission.source(id: admissionID)!
    precondition(!admission.startProjectSourceSummary(admissionID, options: .init(length: .concise),
      expectedSource: expected, configurationIdentity: [UUID(), UUID()]))
    admission.projectSources[0].title = "先に変更された資料"
    precondition(!admission.startProjectSourceSummary(admissionID, options: .init(length: .concise),
      expectedSource: expected, configurationIdentity: admission.summaryConfigurationIdentity))
    precondition(admission.source(id: admissionID)?.summaryOptions == nil && admission.sourcePreparationJobs.isEmpty)
  }

  @MainActor static func failuresAndAttribution(_ root: URL) async throws {
    MeetingSummarizer.reset()
    let (model, id) = try await fixture(root, "attribution")
    var source = model.source(id: id)!
    source.summary = "以前の原文の要約"
    source.summaryTextReference = "previous-original.json"
    source.summaryStatus = .ready
    precondition(model.storeProjectSource(source))
    MeetingSummarizer.outcome = .failure(.network)
    await model.summarizeProjectSource(id)
    let failed = model.source(id: id)!
    precondition(failed.summary == source.summary && failed.summaryTextReference == "previous-original.json")
    precondition(failed.summaryAttemptTextReference == source.extractedTextReference && failed.summaryStatus == .failed)
    await model.summarizeProjectSource(id)
    precondition(MeetingSummarizer.calls.count == 1)
    MeetingSummarizer.outcome = .success(.init(markdown: "新しい原文の要約"))
    let retryOptions = SourceSummaryOptions(length: .concise, engineChoice: .onDevice)
    precondition(model.startProjectSourceSummary(id, options: retryOptions,
      expectedSource: failed, configurationIdentity: model.summaryConfigurationIdentity))
    await model.sourcePreparationJobs[id]!.task.value
    let rewritten = model.source(id: id)!
    precondition(rewritten.summaryTextReference == source.extractedTextReference && rewritten.summaryAttemptTextReference == source.extractedTextReference)
    precondition(rewritten.summary == "新しい原文の要約" && rewritten.summaryHistory == [source.summary!])
    precondition(MeetingSummarizer.calls.last?.input.preferences.length == .concise)

    var removedTemplate = rewritten
    removedTemplate.summaryOptions = .init(templateID: "no-longer-present")
    precondition(model.storeProjectSource(removedTemplate))
    await model.summarizeProjectSource(id, retry: true)
    precondition(model.source(id: id)?.summaryStatus == .unavailable && MeetingSummarizer.calls.count == 2)
    precondition(model.source(id: id)?.summaryTextReference == source.extractedTextReference)
  }

  @MainActor static func sqlFailure(_ root: URL) async throws {
    MeetingSummarizer.reset()
    let (model, id) = try await fixture(root, "sql-failure")
    let before = model.source(id: id)!
    try execute("CREATE TRIGGER reject_write BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", model: model)
    precondition(!model.startProjectSourceSummary(id, options: .init(length: .detailed),
      expectedSource: before, configurationIdentity: model.summaryConfigurationIdentity))
    precondition(model.source(id: id) == before && model.sourcePreparationJobs.isEmpty && MeetingSummarizer.calls.isEmpty)
    try execute("DROP TRIGGER reject_write;", model: model)
    let gate = SourceSummaryGate()
    MeetingSummarizer.gate = gate
    precondition(model.startProjectSourceSummary(id, options: .init(), expectedSource: before,
      configurationIdentity: model.summaryConfigurationIdentity))
    let job = model.sourcePreparationJobs[id]!.task
    await gate.entered()
    try execute("CREATE TRIGGER reject_write BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", model: model)
    gate.resume()
    await job.value
    precondition(model.source(id: id)?.summaryStatus != .ready && model.source(id: id)?.summary == before.summary)
    let durable = try reload(model)
    precondition(durable.first?.summaryStatus != .ready)
    try execute("DROP TRIGGER reject_write;", model: model)
    precondition(model.recoverInterruptedProjectSources() && model.source(id: id)?.summaryStatus == .failed)
  }

  @MainActor static func race(_ root: URL, change: Int) async throws {
    MeetingSummarizer.reset()
    let (model, id) = try await fixture(root, "race-\(change)")
    let registeredID = UUID()
    model.registeredLLMs.models = [.init(id: registeredID, selection: .init(modelID: "registered"))]
    let custom = SummaryMarketTemplate(id: "custom", title: "選んだ形式", detail: "", symbol: .docText, lead: "選んだ形式")
    model.choices.append(.market(custom))
    var source = model.source(id: id)!
    source.summary = "保持する以前の要約"
    source.summaryTextReference = "previous-body.json"
    source.privacy.classification = .general
    source.privacy.allowsCloudAI = true
    precondition(model.storeProjectSource(source))
    let options = SourceSummaryOptions(templateID: custom.id, engineChoice: .registered(registeredID))
    let gate = SourceSummaryGate()
    MeetingSummarizer.gate = gate
    precondition(model.startProjectSourceSummary(id, options: options, expectedSource: source,
      configurationIdentity: model.summaryConfigurationIdentity))
    let job = model.sourcePreparationJobs[id]!.task
    await gate.entered()
    switch change {
    case 0: model.currentTeamID = "other"; model.currentTeamID = nil
    case 1: model.isRestoring = true
    case 2: model.isStoreProtected = true
    case 3: model.projectSources[0].privacy.revokeExternalPermissions()
    case 4: model.projectSources = []
    case 5: model.projectSources[0].extractedTextReference = "replacement.json"
    case 6: model.projectSources[0].summaryOptions = .init(length: .concise)
    case 7: model.choices.removeAll { $0.id == custom.id }
    case 8: model.summaryPreferences.length = .concise
    case 9: model.registeredLLMs.models = []
    case 10: model.summaryConfigurationIdentity = [UUID(), UUID()]
    case 11: model.projectSources[0].title = "変更された資料名"
    default: job.cancel()
    }
    gate.resume()
    await job.value
    precondition(MeetingSummarizer.allowed == [false])
    if let remaining = model.source(id: id) {
      precondition(remaining.summary == source.summary && remaining.summaryTextReference == source.summaryTextReference)
    }
    precondition(model.tasks.isEmpty && model.sourcePreparationJobs.isEmpty && model.projectSourceProcessingIDs.isEmpty)
  }

  @MainActor static func reload(_ model: MemoraModel) throws -> [ProjectSource] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let data) = store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Missing durable sources") }
    return try JSONDecoder().decode([ProjectSource].self, from: data)
  }

  @MainActor static func execute(_ sql: String, model: MemoraModel) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(model.storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
  }
}
