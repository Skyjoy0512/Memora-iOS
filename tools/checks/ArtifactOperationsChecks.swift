import Foundation
import SQLite3

/// Phase 2: generation → save → reload → edit → export hand-off, and the
/// attribution rows that lead back to the source records. Only OS file/DB
/// boundaries are fixtures; the writers, store and provenance code are real.
@main
struct ArtifactOperationsChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MemoraArtifactOperations-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let files = root.appendingPathComponent("workspace", isDirectory: true)
    setenv("MEMORA_WORKSPACE_FILES_DIRECTORY", files.path, 1)

    try await saveReloadEdit(root: root)
    try await failedSaveDoesNotReportSuccess(root: root)
    try shareCopyLifetime(root: root)
    try sourceRowsRespectDeletionPrivacyAndWorkspace()
    print("ArtifactOperationsChecks: passed (real DOCX/PPTX files, production save/edit/reload, SQLite ABORT leaves no success, share copy cleanup, source rows for deleted/revoked/other workspace; share destination and Office final rendering unverified)")
  }

  @MainActor static func saveReloadEdit(root: URL) async throws {
    let storeURL = root.appendingPathComponent("artifacts.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    let person = Person(id: UUID(), name: "架空の田中", note: "提案先", contactIdentifier: nil, privacy: grantedPrivacy())
    let meeting = Meeting(title: "架空の提案会議", participantIDs: [person.id], privacy: grantedPrivacy())
    let task = MemoraTask(id: UUID(), title: "概算を出す", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: grantedPrivacy())
    model.people = [person]; model.meetings = [meeting]; model.tasks = [task]
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.message.sources = [AIChatSource(meetingID: meeting.id, title: meeting.title)]
    model.recordCloudReads([.person(person.id), .meeting(meeting.id), .task(task.id)], messageID: model.message.id)

    var document = MemoraDocument(title: "架空の提案", kind: .document,
      markdown: "# 提案\n\n- 概算を出す")
    document.provenance = model.artifactProvenance(for: model.message)
    document = try await model.prepareDocumentArtifact(document,
      call: AgentToolCall(id: "doc", name: "create_document", arguments: [:]))
    guard let originalName = document.artifactFileReference, let originalURL = ProjectSourceFiles.resolve(originalName) else {
      preconditionFailure("artifact file missing")
    }
    precondition(FileManager.default.fileExists(atPath: originalURL.path))
    precondition(model.addDocument(document))

    var reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("documents missing") }
    var stored = try JSONDecoder().decode([MemoraDocument].self, from: data)
    precondition(stored.count == 1 && stored[0].artifactFileReference == originalName)
    precondition(stored[0].provenance?.records.contains { $0.target == .task(task.id) } == true)

    precondition(model.updateDocument(stored[0].id, title: "編集した提案", body: "# 編集後\n\n- 概算を確認済み"))
    reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let editedData) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("edited document missing") }
    stored = try JSONDecoder().decode([MemoraDocument].self, from: editedData)
    precondition(stored[0].title == "編集した提案" && stored[0].markdown.contains("概算を確認済み"))
    precondition(stored[0].artifactFileReference == originalName && stored[0].hasOutdatedArtifact)
    precondition(stored[0].contentRevision == 1 && stored[0].artifactRevision == 0)
    precondition(stored[0].provenance?.isValid == true)
    precondition(FileManager.default.fileExists(atPath: originalURL.path))
    var editedWord = try OfficeArchiveReader(data: DOCXWriter.data(for: stored[0]))
    let editedText = try OfficeDocumentExtraction.read(archive: &editedWord, extension: "docx").blocks.map(\.text).joined()
    precondition(editedText.contains("概算を確認済み") && !editedText.contains("概算を出す"))
    let settled = model.documents
    precondition(!model.updateDocument(document.id, title: "古い画面", body: "上書き禁止", expectedUpdatedAt: document.updatedAt))
    precondition(model.documents == settled)
    model.isRestoring = true
    precondition(!model.updateDocument(document.id, title: "復元中", body: "上書き禁止"))
    model.isRestoring = false

    let templateBytes = PPTXWriter.data(for: MemoraDocument(title: "会社原本", kind: .slides,
      slides: [DocumentSlide(title: "{{title}}", bullets: ["{{body}}"], notes: "元のノート")]))
    let templateName = try await ProjectSourceFiles.shared.write(templateBytes, extension: "pptx")
    let template = CompanyTemplate(name: "会社原本", format: .pptx, fileReference: templateName,
      analysis: try CompanyTemplateEngine.analyze(templateBytes, format: .pptx))
    model.companyTemplates = [template]
    var company = MemoraDocument(title: "会社資料", kind: .slides, slides: [DocumentSlide(title: "生成内容", bullets: ["要点"])])
    company = try await model.prepareDocumentArtifact(company, call: AgentToolCall(id: "company", name: "create_slides", arguments: [
      "template_id": template.id.uuidString, "template_fields": [["name": "title", "value": "生成内容"], ["name": "body", "value": "要点"]]
    ]))
    precondition(model.addDocument(company))
    let generatedURL = ProjectSourceFiles.resolve(company.artifactFileReference!)!
    let generatedBytes = try Data(contentsOf: generatedURL)
    precondition(model.updateDocument(company.id, title: "編集した会社資料", body: "# 編集後\n- 新しい要点"))
    let companyAfter = model.documents.first { $0.id == company.id }!
    precondition(companyAfter.companyTemplateID == template.id && companyAfter.hasOutdatedArtifact)
    precondition(companyAfter.artifactFileReference == company.artifactFileReference && companyAfter.artifactFormat == "PPTX")
    let preserved = try Data(contentsOf: generatedURL)
    let original = try Data(contentsOf: ProjectSourceFiles.resolve(templateName)!)
    precondition(preserved == generatedBytes && original == templateBytes)
    var referenceToOriginal = company
    referenceToOriginal.id = UUID(); referenceToOriginal.artifactFileReference = templateName
    precondition(model.addDocument(referenceToOriginal))
    model.deleteDocument(referenceToOriginal.id)
    await Task.yield()
    precondition(FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(templateName)!.path))

    // A slide deck follows the same save/reload path and keeps its outline.
    var slides = MemoraDocument(title: "架空の報告", kind: .slides,
      slides: [DocumentSlide(title: "報告", bullets: ["決定事項"])])
    slides.provenance = model.artifactProvenance(for: model.message)
    slides = try await model.prepareDocumentArtifact(slides,
      call: AgentToolCall(id: "slides", name: "create_slides", arguments: [:]))
    guard let slideName = slides.artifactFileReference else { preconditionFailure("slides file missing") }
    precondition(model.addDocument(slides))
    reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let slideData) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("slides missing") }
    let storedSlides = try JSONDecoder().decode([MemoraDocument].self, from: slideData)
    precondition(storedSlides.contains { $0.artifactFileReference == slideName && $0.slides.first?.title == "報告" })

    // Mail drafts are saved as local drafts, never as sent mail.
    let draft = MailDraft(recipients: [], subject: "確認のお願い",
      body: "概算を確認します。", workspaceID: model.currentTeamID,
      provenance: model.artifactProvenance(for: model.message))
    precondition(model.saveMailDraft(draft))
    var editedDraft = model.mailDrafts[0]
    editedDraft.subject = "編集した件名"; editedDraft.body = "編集した本文"
    precondition(model.saveMailDraft(editedDraft))
    reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let draftData) = reopened.readOutcome("memora.mailDrafts.v1") else { preconditionFailure("drafts missing") }
    let storedDrafts = try JSONDecoder().decode([MailDraft].self, from: draftData)
    precondition(storedDrafts.count == 1 && storedDrafts[0].subject == "編集した件名")
    precondition(storedDrafts[0].status == .draft && storedDrafts[0].recipients.isEmpty)
  }

  @MainActor static func failedSaveDoesNotReportSuccess(root: URL) async throws {
    let storeURL = root.appendingPathComponent("failure.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    let existing = MemoraDocument(title: "保存済み", kind: .document, markdown: "保存済み本文", artifactFileReference: "keep.docx", artifactFormat: "DOCX")
    precondition(model.addDocument(existing))
    let before = model.documents
    var db: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_documents BEFORE INSERT ON documents WHEN NEW.key = 'documents' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    let document = MemoraDocument(title: "保存できない資料", kind: .document, markdown: "本文")
    precondition(!model.addDocument(document))
    precondition(!model.updateDocument(existing.id, title: "保存失敗", body: "書き込めない本文"))
    precondition(model.documents == before)
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let unchanged) = reopened.readOutcome(MemoraModel.StorageKey.documents) else { preconditionFailure("existing data lost") }
    let reloaded = try JSONDecoder().decode([MemoraDocument].self, from: unchanged)
    precondition(reloaded == before)

    var draft = MailDraft(recipients: [], subject: "保存できない下書き", body: "本文", workspaceID: model.currentTeamID)
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_drafts BEFORE INSERT ON documents WHEN NEW.key = 'memora.mailDrafts.v1' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!model.saveMailDraft(draft))
    precondition(model.mailDrafts.isEmpty)
    draft.subject = "再試行"
    model.rejectWrites = true
    precondition(!model.saveMailDraft(draft))
    precondition(model.mailDrafts.isEmpty)
  }

  static func shareCopyLifetime(root: URL) throws {
    let source = root.appendingPathComponent("source.docx")
    let bytes = Data("架空のDOCX".utf8)
    try bytes.write(to: source)
    let copy = try ArtifactExportFile.copy(source, preferredName: "提案", suffix: "docx")
    precondition(copy.isFileURL && copy.lastPathComponent.hasSuffix(".docx"))
    let copied = try Data(contentsOf: copy)
    precondition(copied == bytes)
    precondition(FileManager.default.fileExists(atPath: source.path))
    ArtifactExportFile.removeTemporary([copy])
    precondition(!FileManager.default.fileExists(atPath: copy.path))
    precondition(FileManager.default.fileExists(atPath: source.path))
    ArtifactExportFile.removeTemporary([source, root])
    precondition(FileManager.default.fileExists(atPath: source.path))
    let link = FileManager.default.temporaryDirectory.appendingPathComponent("export-link-\(UUID()).docx")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    defer { try? FileManager.default.removeItem(at: link) }
    ArtifactExportFile.removeTemporary([link])
    precondition(FileManager.default.fileExists(atPath: link.path))
    precondition(FileManager.default.fileExists(atPath: source.path))
    let unsafe = try ArtifactExportFile.copy(source, preferredName: "../../別/提案", suffix: "docx")
    precondition(unsafe.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL)
    precondition(!unsafe.lastPathComponent.contains("/") && unsafe.lastPathComponent.hasSuffix(".docx"))
    ArtifactExportFile.removeTemporary([unsafe])
    do {
      _ = try ArtifactExportFile.copy(root.appendingPathComponent("missing.docx"), preferredName: "欠落", suffix: "docx")
      preconditionFailure("missing artifact exported")
    } catch {}
  }

  @MainActor static func sourceRowsRespectDeletionPrivacyAndWorkspace() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraArtifactRows-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = try MemoraModel(storeURL: root.appendingPathComponent("rows.sqlite"))
    let personID = UUID(), meetingID = UUID(), taskID = UUID(), journalID = UUID()
    let grant = grantedPrivacy()
    model.people = [Person(id: personID, name: "架空の田中", note: "メモ", contactIdentifier: nil, privacy: grant)]
    model.meetings = [Meeting(id: meetingID, title: "会議", privacy: grant)]
    model.tasks = [MemoraTask(id: taskID, title: "作業", isCompleted: false, privacy: grant)]
    model.lifeLogEntries = [LifeLogEntry(id: journalID, createdAt: .now, title: "メモ", summary: "本文",
      source: .iphone, privacy: grant)]
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    model.recordCloudReads([.person(personID), .meeting(meetingID), .task(taskID), .journal(journalID)],
      messageID: model.message.id)
    let provenance = model.artifactProvenance(for: model.message)
    var rows = model.artifactSourceRows(provenance: provenance)
    precondition(rows.count == 4 && rows.allSatisfy(\.canOpen))

    model.people.removeAll()
    rows = model.artifactSourceRows(provenance: provenance)
    let missing = rows.first { $0.target == .record(.person(personID)) }!
    precondition(!missing.canOpen)

    model.people = [Person(id: personID, name: "架空の田中", note: "メモ", contactIdentifier: nil, privacy: grant)]
    model.people[0].privacy.allowsCloudAI = false
    rows = model.artifactSourceRows(provenance: provenance)
    let revoked = rows.first { $0.target == .record(.person(personID)) }!
    precondition(revoked.canOpen && !revoked.allowsCloudAI)

    model.currentTeamID = "other-workspace"
    precondition(model.artifactSourceRows(provenance: provenance).isEmpty)
    model.currentTeamID = nil
    model.isStoreProtected = true
    precondition(model.artifactSourceRows(provenance: provenance).isEmpty)
    model.isStoreProtected = false
    model.isRestoring = true
    precondition(!model.canOpenArtifactSource(.record(.meeting(meetingID)), workspaceID: nil))
  }

  static func waitUntil(_ condition: @escaping () -> Bool) async -> Bool {
    for _ in 0..<50 {
      if condition() { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }

  static func grantedPrivacy() -> RecordPrivacy {
    var privacy = RecordPrivacy(classification: .personal)
    privacy.allowsCloudAI = true
    return privacy
  }
}
