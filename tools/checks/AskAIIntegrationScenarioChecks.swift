import Foundation
import SQLite3

/// A〜Eの統合シナリオを、外部へ通信せず本番のドメイン処理へ通す。
/// HTTP・OAuth・OSサービス・モデル応答・承認UIだけをfixtureに置き換える。
@main
struct AskAIIntegrationScenarioChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MemoraAskAIScenarios-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("workspace", isDirectory: true)
    setenv("MEMORA_WORKSPACE_FILES_DIRECTORY", files.path, 1)

    try await personToCompanyProposal(root: root)
    try pastConversationToOpenItems()
    try await researchHTTPBoundary()
    try await researchToCompanySlides(root: root)
    try await researchProjectRollback(root: root)
    try await meetingToMailDraft(root: root)
    try await mentionSelectsOnlyPermittedTools(root: root)

    print("AskAIIntegrationScenarioChecks: passed (A template DOCX/PPTX -> real file -> SQLite; B episode reuse revoked by task/workspace/deletion; C bounded research -> sources/report atomic SQLite save/reopen -> project DOCX/PPTX/edit, partial coverage, 9 suspended-write rollback races; D meeting draft approval/save/edit/reload, unknown recipient refused; E production registry/policy selection; model/HTTP/OS/approval fixtures, no network/keys/user data)")
  }

  // MARK: - A. 人物 → 会社提案書

  @MainActor static func personToCompanyProposal(root: URL) async throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("proposal.sqlite"))
    let person = Person(id: UUID(), name: "架空の田中", note: "提案の窓口",
      contactIdentifier: nil, privacy: grantedPrivacy())
    let meeting = Meeting(title: "架空の提案会議", participantIDs: [person.id], privacy: grantedPrivacy(),
      decisions: ["次回までに概算を出す"], openQuestions: ["予算の上限は未確認"])
    let task = MemoraTask(id: UUID(), title: "概算を作る", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: grantedPrivacy())
    var closedPrivacy = RecordPrivacy(classification: .personal)
    closedPrivacy.allowsCloudAI = false
    let secretTask = MemoraTask(id: UUID(), title: "非公開タスク", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: closedPrivacy)
    let secretMeeting = Meeting(title: "非公開会議", participantIDs: [person.id], privacy: closedPrivacy)
    model.people = [person, Person(id: UUID(), name: person.name, note: "别人の非公開メモ",
      contactIdentifier: nil, privacy: grantedPrivacy())]
    model.meetings = [meeting, secretMeeting]
    model.tasks = [task, secretTask]
    let messageID = model.message.id
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.message.sources = [AIChatSource(meetingID: meeting.id, title: meeting.title)]
    let read = model.readPersonTool(AgentToolCall(id: "proposal-person", name: "read_person",
      arguments: ["person_id": person.id.uuidString]), messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(!read.isError && read.text.contains("概算を作る"))
    precondition(!read.text.contains("非公開タスク") && !read.text.contains("非公開会議"))
    let provenance = model.artifactProvenance(for: model.message)
    precondition(provenance.records.contains { $0.target == .task(task.id) })
    precondition(!provenance.records.contains { $0.target == .task(secretTask.id) })
    precondition(!provenance.records.contains { $0.target == .meeting(secretMeeting.id) })

    let body = "# 提案\n\n## 決定事項\n- 次回までに概算を出す\n\n## 未確認\n- 予算の上限"
    for (kind, suffix) in [(MemoraDocumentKind.document, "docx"), (.slides, "pptx")] {
      let templateDocument: MemoraDocument
      if kind == .document {
        templateDocument = MemoraDocument(title: "{{title}}", kind: .document, markdown: "{{body}}")
      } else {
        templateDocument = MemoraDocument(title: "{{title}}", kind: .slides,
          slides: [DocumentSlide(title: "{{title}}", bullets: ["{{body}}"])])
      }
      let templateBytes = kind == .document ? try DOCXWriter.data(for: templateDocument) : PPTXWriter.data(for: templateDocument)
      let analysis = try CompanyTemplateEngine.analyze(templateBytes, format: kind == .document ? .docx : .pptx)
      precondition(analysis.placeholders == ["body", "title"] && analysis.isAvailable)
      let reference = try await ProjectSourceFiles.shared.write(templateBytes, extension: suffix)
      let template = CompanyTemplate(name: "架空の会社書式", format: kind == .document ? .docx : .pptx,
        fileReference: reference, workspaceID: nil, analysis: analysis)
      model.companyTemplates = [template]

      var document = MemoraDocument(title: "顧客提案", kind: kind, spaceID: nil)
      document.markdown = body
      document.slides = kind == .slides ? [DocumentSlide(title: "顧客提案", bullets: ["次回までに概算を出す"])] : []
      document.provenance = provenance
      let call = AgentToolCall(id: UUID().uuidString, name: kind == .document ? "create_document" : "create_slides",
        arguments: ["template_id": template.id.uuidString, "template_fields": [
          ["name": "title", "value": "架空商事 ご提案"],
          ["name": "body", "value": body]
        ]])
      document = try await model.prepareDocumentArtifact(document, call: call)
      precondition(document.companyTemplateID == template.id)
      precondition(document.artifactFormat?.lowercased() == suffix)
      guard let name = document.artifactFileReference, let url = ProjectSourceFiles.resolve(name) else {
        preconditionFailure("A: generated artifact missing")
      }
      let bytes = try Data(contentsOf: url)
      var archive = try OfficeArchiveReader(data: bytes)
      let extracted = try OfficeDocumentExtraction.read(archive: &archive, extension: suffix)
      let text = extracted.blocks.map(\.text).joined(separator: " ")
      precondition(text.contains("架空商事 ご提案") && text.contains("次回までに概算を出す"))
      let reanalyzed = try CompanyTemplateEngine.analyze(bytes, format: kind == .document ? .docx : .pptx)
      precondition(reanalyzed.placeholders.isEmpty)
      precondition(model.addDocument(document))

      let reopened = LocalStore(fileURL: root.appendingPathComponent("proposal.sqlite")); try reopened.prepare()
      guard case .data(let data) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("A: documents not stored") }
      let stored = try JSONDecoder().decode([MemoraDocument].self, from: data)
      precondition(stored.first?.artifactFileReference == name && stored.first?.provenance?.isValid == true)
      precondition(stored.first?.provenance?.records.contains { $0.target == .task(task.id) } == true)
      precondition(stored.first?.provenance?.records.contains { $0.target == .task(secretTask.id) } == false)
    }
    model.currentTeamID = "different-workspace"
    do {
      _ = try await model.prepareDocumentArtifact(MemoraDocument(title: "別WS", kind: .slides),
        call: AgentToolCall(id: UUID().uuidString, name: "create_slides", arguments: [
          "template_id": model.companyTemplates[0].id.uuidString,
          "template_fields": [["name": "title", "value": "別"], ["name": "body", "value": "別"]]
        ]))
      preconditionFailure("A: template from another workspace reused")
    } catch CompanyTemplateEngine.Failure.unsupported {}
  }

  // MARK: - B. 過去会話 → 未完了事項

  static func pastConversationToOpenItems() throws {
    let task = MemoraTask(id: UUID(), title: "見積もりを確認する", isCompleted: false, privacy: grantedPrivacy())
    let oldReference = AIRecordReference(target: .task(task.id), fingerprint: AIRecordFingerprint.make(task)!)
    let provenance = AIConversationProvenance(references: [oldReference], workspaceID: nil, memoryFingerprint: "memory")
    func reuse(resolve: (RecordPrivacyTarget) -> AIRecordReference?, workspace: String? = nil) -> Bool {
      provenance.allowsReuse(workspaceID: workspace, memoryFingerprint: "memory", resolve: resolve, allows: { _ in true })
    }
    precondition(reuse { _ in oldReference })
    var completed = task; completed.isCompleted = true
    let current = AIRecordReference(target: .task(task.id), fingerprint: AIRecordFingerprint.make(completed)!)
    precondition(!reuse { _ in current })
    precondition(!reuse { _ in nil })
    precondition(!reuse(resolve: { _ in oldReference }, workspace: "other"))
    precondition(!provenance.allowsReuse(workspaceID: nil, memoryFingerprint: "changed",
      resolve: { _ in oldReference }, allows: { _ in true }))
    var incomplete = provenance
    incomplete.isComplete = false
    precondition(!incomplete.allowsReuse(workspaceID: nil, memoryFingerprint: "memory",
      resolve: { _ in oldReference }, allows: { _ in true }))

    let wanted = MemoryRetrievalItem(id: UUID(), kind: .episode,
      text: "見積もりを確認する作業が未完了", updatedAt: .now, sourceID: UUID())
    let unrelated = MemoryRetrievalItem(id: UUID(), kind: .episode,
      text: "旅行の宿泊先を相談", updatedAt: .now, sourceID: UUID())
    let otherWorkspace = MemoryRetrievalItem(id: UUID(), kind: .episode,
      text: wanted.text, updatedAt: .now, workspaceID: "other", sourceID: UUID())
    let found = try MemoryRetrievalOrchestrator.retrieve("見積もり 確認", candidates: [unrelated, otherWorkspace, wanted],
      workspaceID: nil, personID: nil)
    precondition(found.count == 1 && found.first?.item.id == wanted.id)
    let ambiguous = try MemoryRetrievalOrchestrator.retrieve("その件", candidates: [wanted], workspaceID: nil, personID: nil)
    precondition(ambiguous.isEmpty)
    let episode = AIEpisode(id: UUID(), sessionID: UUID(), date: .now, topic: "見積もり",
      objective: "未完了事項の確認", summary: "見積もりの確認が残っている", unresolved: ["見積もりを確認する"],
      workspaceID: nil, provenance: provenance)
    let encoded = try JSONEncoder().encode(episode)
    let decoded = try JSONDecoder().decode(AIEpisode.self, from: encoded)
    precondition(decoded.unresolved == ["見積もりを確認する"] && decoded.decisions.isEmpty)
  }

  @MainActor static func researchHTTPBoundary() async throws {
    let searchJSON = Data(#"{"web":{"results":[{"url":"https://example.invalid/a?utm_source=x","title":"架空A","description":"<b>概要A</b>"},{"url":"https://example.invalid/a","title":"重複A","description":"別の概要"},{"url":"https://example.invalid/b","title":"架空B","description":"概要B"}]}}"#.utf8)
    let deepJSON = Data(#"{"grounding":{"generic":[{"url":"https://example.invalid/c","title":"架空C","snippets":["抽出本文C1","抽出本文C2"],"page_age":"2026-10-01T00:00:00Z"}]}}"#.utf8)
    BraveFixtureProtocol.responses = [(200, searchJSON), (200, deepJSON)]
    BraveFixtureProtocol.requests = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BraveFixtureProtocol.self]
    let search = try await WebResearchClient.search(query: "架空 市場", mode: .search, key: "offline-fixture-brave",
      sessionConfiguration: configuration)
    precondition(search.count == 2 && search.allSatisfy { $0.kind == .searchExcerpt })
    precondition(search[0].url.absoluteString == "https://example.invalid/a")
    precondition(!search[0].text.contains("<b>") && search[0].text.contains("概要A"))
    let deep = try await WebResearchClient.search(query: "架空 市場", mode: .deepResearch, key: "offline-fixture-brave",
      sessionConfiguration: configuration)
    precondition(deep.count == 1 && deep[0].kind == .extractedPassage)
    precondition(deep[0].text.contains("抽出本文C1") && deep[0].publishedAt != nil)
    let requests = BraveFixtureProtocol.requests
    precondition(requests.count == 2)
    precondition(requests[0].url?.host == "api.search.brave.com" && requests[0].url?.path == "/res/v1/web/search")
    precondition(requests[0].value(forHTTPHeaderField: "X-Subscription-Token") == "offline-fixture-brave")
    precondition(requests[1].url?.path == "/res/v1/llm/context")
    precondition(requests[1].url?.query?.contains("maximum_number_of_urls=6") == true)
  }

  // MARK: - C. Research → 会社PPTX

  @MainActor static func researchToCompanySlides(root: URL) async throws {
    let first = WebResearchSource(title: "架空の一次資料", url: URL(string: "https://example.invalid/a")!,
      text: "市場は拡大している", kind: .searchExcerpt)
    let sameURL = WebResearchSource(title: "重複", url: first.url, text: "別の抜粋", kind: .extractedPassage)
    let second = WebResearchSource(title: "架空の比較資料", url: URL(string: "https://example.invalid/b")!,
      text: "課題は人材確保", kind: .extractedPassage)
    var calls: [String] = []
    let plan = WebResearchReport(query: "架空市場", mode: .deepResearch, queries: ["架空市場", "市場 統計", "市場 比較"])
    var report = await ResearchLoop.run(plan, isAuthorized: { true }, search: { query in
      calls.append(query)
      return [first, sameURL, second]
    }, publish: { _ in true })
    precondition(calls.count > 3 && calls.count <= ResearchPlan.maximumSearches && Set(calls).count == calls.count)
    precondition(report.sources.count == 2 && (report.coverageGaps ?? []).isEmpty == false)
    precondition(report.sources.contains { $0.kind == .searchExcerpt } && report.sources.contains { $0.kind == .extractedPassage })
    precondition(!ResearchPlan.hasInvalidCitations("根拠【Web1】【Web2】", sourceCount: 2))
    precondition(ResearchPlan.hasInvalidCitations("根拠【Web3】", sourceCount: 2))
    var failed = await ResearchLoop.run(plan, isAuthorized: { true }, search: { _ in throw CancellationError() }, publish: { _ in true })
    precondition(failed.status == .interrupted && failed.sources.isEmpty)
    failed.answer = "取得済みの根拠です。"
    precondition(failed.status != .complete)

    let model = try MemoraModel(storeURL: root.appendingPathComponent("research.sqlite"))
    let projectID = UUID()
    model.spaces = [FixtureSpace(id: projectID, name: "架空の調査プロジェクト")]
    report.status = .interrupted
    report.answer = "市場は拡大【Web1】、人材確保が課題【Web2】。未確認項目あり。"
    report.citedSourceIDs = report.sources.map(\.id)
    precondition(model.storeWebResearch(report))
    let projectSaved = try await model.saveWebResearch(report.id, to: projectID)
    precondition(projectSaved && model.projectSources.count == 3)
    let storedReport = model.webResearch(id: report.id)!
    precondition(storedReport.status == .interrupted && storedReport.savedProjectID == projectID)
    precondition(storedReport.savedSourceIDs.count == 2 && storedReport.savedNoteID != nil)
    for source in model.projectSources {
      guard let name = source.extractedTextReference, let url = ProjectSourceFiles.resolve(name) else { preconditionFailure("Missing research excerpt") }
      let blocks = try JSONDecoder().decode([ProjectSourceText].self, from: Data(contentsOf: url))
      precondition(!blocks.isEmpty && source.projectID == projectID)
      if source.kind == .web {
        precondition(source.textCoverage == .partial && source.metadata?["retrievedAt"] != nil)
        precondition(report.sources.contains { $0.url == source.originalURL && $0.text == blocks[0].text })
      } else {
        precondition(source.textCoverage == .complete && blocks[0].text.contains("調査は未完了です"))
        precondition(report.sources.allSatisfy { blocks[0].text.contains($0.url.absoluteString) })
      }
      model.recordArtifactProjectSource(AgentSourceReference(id: source.id, projectID: projectID,
        fingerprint: AIRecordFingerprint.make(source)!), messageID: model.message.id)
    }
    let repeatedSave = try await model.saveWebResearch(report.id, to: projectID)
    precondition(!repeatedSave && model.projectSources.count == 3)
    let templateDocument = MemoraDocument(title: "{{title}}", kind: .slides,
      slides: [DocumentSlide(title: "{{title}}", bullets: ["{{body}}"])])
    let templateBytes = PPTXWriter.data(for: templateDocument)
    let analysis = try CompanyTemplateEngine.analyze(templateBytes, format: .pptx)
    let reference = try await ProjectSourceFiles.shared.write(templateBytes, extension: "pptx")
    let template = CompanyTemplate(name: "架空の報告書式", format: .pptx,
      fileReference: reference, workspaceID: nil, analysis: analysis)
    model.companyTemplates = [template]
    var document = MemoraDocument(title: "架空市場の調査", kind: .slides,
      slides: [DocumentSlide(title: "架空市場の調査", bullets: ["根拠は【Web1】【Web2】", "未完了の項目あり"])])
    document.spaceID = projectID
    document.provenance = model.artifactProvenance(for: model.message)
    let call = AgentToolCall(id: UUID().uuidString, name: "create_slides", arguments: [
      "template_id": template.id.uuidString,
      "template_fields": [["name": "title", "value": "架空市場の調査"], ["name": "body", "value": "根拠は【Web1】【Web2】"]]
    ])
    document = try await model.prepareDocumentArtifact(document, call: call)
    guard let name = document.artifactFileReference, let url = ProjectSourceFiles.resolve(name) else {
      preconditionFailure("C: PPTX missing")
    }
    let bytes = try Data(contentsOf: url)
    var archive = try OfficeArchiveReader(data: bytes)
    let extracted = try OfficeDocumentExtraction.read(archive: &archive, extension: "pptx")
    precondition(extracted.blocks.map(\.text).joined().contains("根拠は【Web1】【Web2】"))
    precondition(model.addDocument(document))
    let reopened = LocalStore(fileURL: root.appendingPathComponent("research.sqlite")); try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("C: slides not stored") }
    let storedSlides = try JSONDecoder().decode([MemoraDocument].self, from: data)
    precondition(storedSlides.first?.artifactFileReference == name && storedSlides.first?.spaceID == projectID)
    precondition(storedSlides.first?.provenance?.projectSources.count == 3)
    let savedSources: [ProjectSource] = try reload(MemoraModel.StorageKey.projectSources, store: reopened)
    let savedReports: [WebResearchReport] = try reload("memora.webResearch.v1", store: reopened)
    precondition(savedSources == model.projectSources && savedReports == model.webResearchReports)

    var written = MemoraDocument(title: "調査レポート", kind: .document,
      markdown: report.answer + "\n\n" + report.sources.map { $0.url.absoluteString }.joined(separator: "\n"), spaceID: projectID)
    written.provenance = model.artifactProvenance(for: model.message)
    written = try await model.prepareDocumentArtifact(written, call: AgentToolCall(id: "report", name: "create_document", arguments: [:]))
    precondition(model.addDocument(written))
    var docx = try OfficeArchiveReader(data: Data(contentsOf: ProjectSourceFiles.resolve(written.artifactFileReference!)!))
    let docxText = try OfficeDocumentExtraction.read(archive: &docx, extension: "docx").blocks.map(\.text).joined()
    precondition(docxText.contains(report.answer) && report.sources.allSatisfy { docxText.contains($0.url.absoluteString) })
    precondition(model.updateDocument(written.id, title: "再編集した調査レポート", body: "根拠を再確認する。"))
    let edited: [MemoraDocument] = try reload(MemoraModel.StorageKey.documents, store: reopened)
    precondition(edited.first?.title == "再編集した調査レポート" && edited.first?.artifactFileReference == nil)
    precondition(edited.first?.spaceID == projectID && edited.first?.provenance?.projectSources.count == 3)
    let discarded = ProjectSourceFiles.resolve(written.artifactFileReference!)!
    for _ in 0..<10_000 {
      if !FileManager.default.fileExists(atPath: discarded.path) { break }
      await Task.yield()
    }
    precondition(!FileManager.default.fileExists(atPath: discarded.path), "Edited artifact cleanup did not finish")
  }

  @MainActor static func researchProjectRollback(root: URL) async throws {
    for mode in 0..<9 {
      let url = root.appendingPathComponent("research-race-\(mode).sqlite")
      let model = try MemoraModel(storeURL: url)
      let projectID = UUID()
      model.spaces = [FixtureSpace(id: projectID, name: "架空の保存先")]
      var report = WebResearchReport(query: "架空の比較", mode: .deepResearch, queries: ["架空の比較"])
      report.sources = [WebResearchSource(title: "架空の抜粋", url: URL(string: "https://example.invalid/source")!, text: "全文ではない抜粋", kind: .searchExcerpt)]
      precondition(model.storeWebResearch(report))
      precondition(model.persistNow(model.projectSources, forKey: MemoraModel.StorageKey.projectSources))
      let before = try Set(FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
      let entered = DispatchSemaphore(value: 0)
      let release = DispatchSemaphore(value: 0)
      // Hold the real file actor, not a mocked write. The model suspends after
      // capturing its revisions, so execution-time mutations are deterministic.
      let hold = Task.detached { await ProjectSourceFiles.shared.holdForResearchCheck(entered: entered, release: release) }
      defer { release.signal() }
      precondition(entered.wait(timeout: .now() + 10) == .success)
      var started = false
      let operation = Task { @MainActor in
        started = true
        return try await model.saveWebResearch(report.id, to: projectID)
      }
      while !started { await Task.yield() }
      switch mode {
      case 0: model.currentTeamID = "other"
      case 1: model.webResearchReports[0].query = "確認中に変更した質問"
      case 2: model.webResearchReports = []
      case 3: model.spaces = []
      case 4: model.isRestoring = true
      case 5: model.isStoreProtected = true
      case 6: operation.cancel()
      case 7: model.webResearchBusyIDs.insert(report.id)
      default:
        var connection: OpaquePointer?
        precondition(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        precondition(sqlite3_exec(connection, "CREATE TRIGGER fail_research BEFORE INSERT ON documents WHEN NEW.key='memora.webResearch.v1' BEGIN SELECT RAISE(ABORT, 'research save failure'); END;", nil, nil, nil) == SQLITE_OK)
      }
      release.signal()
      let held = await hold.value
      let saved = try await operation.value
      precondition(held && !saved && model.projectSources.isEmpty)
      let after = try Set(FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
      precondition(after == before, "Research save changed files, case \(mode): added=\(after.subtracting(before)), removed=\(before.subtracting(after))")
      let reopened = LocalStore(fileURL: url); try reopened.prepare()
      let sources: [ProjectSource] = try reload(MemoraModel.StorageKey.projectSources, store: reopened)
      let reports: [WebResearchReport] = try reload("memora.webResearch.v1", store: reopened)
      precondition(sources.isEmpty && reports == [report], "Atomic research save failed, case \(mode)")
    }
  }

  static func reload<Value: Decodable>(_ key: String, store: LocalStore) throws -> Value {
    guard case .data(let data) = store.readOutcome(key) else { preconditionFailure("Missing stored \(key)") }
    return try JSONDecoder().decode(Value.self, from: data)
  }

  // MARK: - D. 会議 → メール下書き

  @MainActor static func meetingToMailDraft(root: URL) async throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("mail.sqlite"))
    let person = Person(id: UUID(), name: "架空の佐藤", note: "会議の参加者",
      contactIdentifier: nil, privacy: grantedPrivacy())
    let meeting = Meeting(title: "架空の定例", participantIDs: [person.id], privacy: grantedPrivacy(),
      decisions: ["次回の日程を調整する"], openQuestions: ["見積もりの期限"])
    let task = MemoraTask(id: UUID(), title: "見積もりを送る", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: grantedPrivacy())
    model.people = [person, Person(id: UUID(), name: person.name, note: "同名の別人の非公開メモ",
      contactIdentifier: nil, privacy: grantedPrivacy())]
    model.meetings = [meeting]
    model.tasks = [task]
    let messageID = model.message.id
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.message.sources = [AIChatSource(meetingID: meeting.id, title: meeting.title)]
    model.recordCloudReads([.meeting(meeting.id), .person(person.id), .task(task.id)], messageID: messageID)
    let read = model.readPersonTool(AgentToolCall(id: "meeting-person", name: "read_person",
      arguments: ["person_id": person.id.uuidString]), messageID: messageID, compact: false, purpose: .cloudAI)
    precondition(!read.isError && read.text.contains("次回の日程を調整する"))
    precondition(read.text.contains("見積もりを送る") && read.text.contains("関連する会議の決定"))
    precondition(!read.text.contains("同名の別人の非公開メモ"))
    var approvals = 0
    model.approvalAction = { approvals += 1; await Task.yield() }
    model.approves = true

    let guessed = AgentToolCall(id: "guess", name: "draft_email",
      arguments: ["to": ["佐藤さん"], "subject": "定例の確認", "body": "次回の日程を調整します。"])
    let refused = await model.draftEmailTool(guessed, messageID: messageID)
    precondition(refused.isError && approvals == 0 && model.mailDrafts.isEmpty)

    let call = AgentToolCall(id: "meeting-draft", name: "draft_email",
      arguments: ["to": [], "subject": "架空の定例の確認", "body": "次回の日程を調整します。見積もりの期限を確認します。"])
    let saved = await model.draftEmailTool(call, messageID: messageID)
    precondition(!saved.isError && approvals == 1 && model.mailDrafts.count == 1)
    var draft = model.mailDrafts[0]
    precondition(draft.recipients.isEmpty && draft.status == .draft)
    precondition(draft.provenance?.records.contains { $0.target == .meeting(meeting.id) } == true)
    precondition(draft.provenance?.records.contains { $0.target == .task(task.id) } == true)
    precondition(draft.provenance?.records.contains { $0.target == .person(person.id) } == true)
    draft.subject = "本人が編集した件名"
    draft.body = "本人が編集した本文"
    precondition(model.saveMailDraft(draft))
    let reopened = LocalStore(fileURL: root.appendingPathComponent("mail.sqlite")); try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome("memora.mailDrafts.v1") else { preconditionFailure("D: draft not stored") }
    let stored = try JSONDecoder().decode([MailDraft].self, from: data)
    precondition(stored.count == 1 && stored[0].subject == "本人が編集した件名" && stored[0].body == "本人が編集した本文")
    precondition(stored[0].recipients.isEmpty && stored[0].status == .draft)

    model.approvalAction = { await Task.yield(); model.tasks[0].title = "承認待ちで変更" }
    let stale = await model.draftEmailTool(AgentToolCall(id: "stale", name: "draft_email",
      arguments: ["to": [], "subject": "変更後", "body": "変更後の本文"]), messageID: messageID)
    precondition(stale.isError && model.mailDrafts.count == 1)
  }

  // MARK: - E. @選択 → 許可されたToolのみ

  static func mentionSelectsOnlyPermittedTools(root: URL) async throws {
    let gmail = tool("memora:search_email", provider: .directAPI, permissions: ["gmail:fixture"], risk: .read)
    let mcp = tool("mcp_fixture", provider: .mcp, permissions: ["mcp:fixture"], risk: .read)
    let document = tool("memora:create_document", provider: .memora, permissions: [], risk: .write)
    var registry = AIToolRegistry()
    for item in [gmail, mcp, document] { precondition(registry.register(item)) }
    let gmailProvider = FixtureToolProvider(identifier: "gmail:fixture", text: "架空のメール")
    let mcpProvider = FixtureToolProvider(identifier: "mcp:fixture", text: "架空のMCP結果")
    let gmailPlugin = AIPlugin(id: "service:gmail", name: "Gmail", summary: "架空", aliases: [], kind: .connected,
      state: .ready, toolIDs: [gmail.id], permissions: ["gmail:fixture"], cost: .unknown, provider: .directAPI, serviceID: "gmail")
    let templateID = UUID()
    let templatePlugin = AIPlugin(id: "template:\(templateID)", name: "架空の会社書式", summary: "架空", aliases: [],
      kind: .template, state: .ready, toolIDs: [document.id], permissions: [], cost: .unknown, provider: .memora,
      serviceID: nil, templateID: templateID)
    var policy = AIPluginExecutionPolicy.forSelection(pluginIDs: [gmailPlugin.id, templatePlugin.id],
      plugins: [gmailPlugin, templatePlugin], onDevice: false)
    precondition(policy.toolIDs == [gmail.id, document.id, "memora:ask_user"])
    precondition(policy.templateIDs == [templateID] && policy.pluginIDs == [gmailPlugin.id, templatePlugin.id])
    precondition(policy.permits("search_email", arguments: ["query": "架空"]))
    let gmailResult = try await registry.execute(gmail.id, arguments: Data(#"{"query":"架空"}"#.utf8),
      through: gmailProvider, policy: policy)
    precondition(gmailResult.text == "架空のメール")
    let gmailCalls = await gmailProvider.calls

    do {
      _ = try await registry.execute(mcp.id, arguments: Data(#"{"query":"架空"}"#.utf8),
        through: mcpProvider, policy: policy)
      preconditionFailure("E: unselected MCP tool ran")
    } catch AIToolRegistry.DispatchFailure.scopeViolation {}
    let mcpCalls = await mcpProvider.calls
    precondition(gmailCalls == 1 && mcpCalls == 0)
    policy.toolIDs.remove(gmail.id)
    do {
      _ = try await registry.execute(gmail.id, arguments: Data(#"{"query":"架空"}"#.utf8),
        through: gmailProvider, policy: policy)
      preconditionFailure("E: deselected Gmail ran")
    } catch AIToolRegistry.DispatchFailure.scopeViolation {}

    registry.tools[mcp.id]?.isEnabled = false
    do {
      _ = try await registry.execute(mcp.id, arguments: Data(#"{"query":"架空"}"#.utf8),
        through: mcpProvider, policy: AIPluginExecutionPolicy(pluginIDs: ["mcp:fixture"],
          toolIDs: [mcp.id], recordIDs: [], limitsRecordReads: false))
      preconditionFailure("E: disconnected MCP ran")
    } catch AIToolRegistry.DispatchFailure.unavailable {}

    precondition(policy.permits("create_document", arguments: ["template_id": templateID.uuidString]))
    precondition(!policy.permits("create_document", arguments: ["template_id": UUID().uuidString]))
    precondition(!policy.permits("draft_email", arguments: [:]))
    let onDevicePolicy = AIPluginExecutionPolicy.forSelection(pluginIDs: [gmailPlugin.id], plugins: [gmailPlugin], onDevice: true)
    precondition(onDevicePolicy.toolIDs == [gmail.id])
    let selectedRecord = UUID(), otherRecord = UUID()
    let record = AIPlugin(id: "record:\(selectedRecord)", name: "指定記録", summary: "fixture", aliases: [],
      kind: .file, state: .ready, toolIDs: ["memora:read_record"], permissions: [], cost: .local,
      provider: .memora, recordID: selectedRecord)
    for kind in [AIPlugin.Kind.skill, .builtin, .connected] {
      let extra = AIPlugin(id: kind == .connected ? "service:notion" : "skill:fixture", name: "追加手順", summary: "fixture", aliases: [],
        kind: kind, state: .ready, toolIDs: ["memora:search_records", "memora:read_record", "memora:read_person"],
        permissions: [], cost: .local, provider: .memora)
      for local in [true, false] {
        let selected = AIPluginExecutionPolicy.forSelection(pluginIDs: [record.id, extra.id], plugins: [record, extra], onDevice: local)
        precondition(selected.limitsRecordReads && selected.recordIDs == [selectedRecord])
        precondition(selected.permits("read_record", arguments: ["id": selectedRecord.uuidString]))
        precondition(!selected.permits("read_record", arguments: ["id": otherRecord.uuidString]))
        precondition(!selected.permits("read_person", arguments: ["person_id": UUID().uuidString]))
        precondition(selected.permits("search_records", arguments: ["query": "fixture"]))
      }
    }
    let templateCall = await gmailProvider.calls
    precondition(templateCall == 1)
  }

  static func tool(_ id: String, provider: AIToolDefinition.Provider, permissions: [String],
                   risk: AIToolDefinition.Risk) -> AIToolDefinition {
    let schema: Data
    if id == "memora:create_document" {
      schema = Data(#"{"type":"object","properties":{"template_id":{"type":"string","format":"uuid"}},"additionalProperties":true}"#.utf8)
    } else {
      schema = Data(#"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}"#.utf8)
    }
    return AIToolDefinition(id: id, name: id.hasPrefix("memora:") ? String(id.dropFirst(7)) : "mcp_fixture",
      summary: "offline fixture", inputSchema: schema, provider: provider, requiredPermissions: permissions,
      risk: risk, isAvailable: true, isEnabled: true)
  }

  static func grantedPrivacy() -> RecordPrivacy {
    var privacy = RecordPrivacy(classification: .personal)
    privacy.allowsCloudAI = true
    return privacy
  }
}

extension ProjectSourceFiles {
  func holdForResearchCheck(entered: DispatchSemaphore, release: DispatchSemaphore) -> Bool {
    entered.signal()
    return release.wait(timeout: .now() + 10) == .success
  }
}

private actor FixtureToolProvider: IntegrationProvider {
  nonisolated let identifier: String
  var calls = 0
  private let text: String
  init(identifier: String, text: String) { self.identifier = identifier; self.text = text }
  func tools() async throws -> [AIToolDefinition] { [] }
  func execute(_ tool: AIToolDefinition, arguments: Data) async throws -> IntegrationToolResult {
    calls += 1
    return IntegrationToolResult(text: text, isError: false)
  }
}


/// Serves only scripted Brave responses; any other request is an error.
final class BraveFixtureProtocol: URLProtocol {
  nonisolated(unsafe) static var responses: [(Int, Data)] = []
  nonisolated(unsafe) static var requests: [URLRequest] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    guard !Self.responses.isEmpty else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
    }
    let (status, data) = Self.responses.removeFirst()
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json", "Content-Length": "\(data.count)"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
