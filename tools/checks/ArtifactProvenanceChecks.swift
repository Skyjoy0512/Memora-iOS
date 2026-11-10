import Foundation

@main enum ArtifactProvenanceChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraArtifactSources-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = root.appendingPathComponent("records.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    let sharedID = UUID(), messageID = UUID(), projectID = UUID()
    var grant = RecordPrivacy(classification: .personal)
    grant.allowsCloudAI = true
    model.people = [Person(id: sharedID, name: "架空の田中", note: "架空のメモ", contactIdentifier: nil, privacy: grant)]
    model.meetings = [Meeting(id: sharedID, title: "会議", participantIDs: [sharedID], privacy: grant)]
    model.tasks = [MemoraTask(id: sharedID, title: "約束した作業", isCompleted: false, privacy: grant)]
    model.lifeLogEntries = [LifeLogEntry(id: sharedID, createdAt: .now, title: "相談メモ", summary: "確認事項", source: .iphone, privacy: grant)]
    model.spaces = [FixtureSpace(id: projectID, name: "架空の案件")]
    let source = ProjectSource(projectID: projectID, kind: .note, title: "参考資料", extractedTextReference: "fixture.txt", processingStatus: .ready, privacy: grant)
    model.projectSources = [source]
    let targets: [RecordPrivacyTarget] = [.meeting(sharedID), .person(sharedID), .task(sharedID), .journal(sharedID)]
    func reset(cloud: Bool = true) {
      model.message = FixtureMessage()
      model.message.id = messageID
      model.message.text = "架空の成果物"
      model.message.sources = [.init(meetingID: sharedID, title: "会議")]
      if cloud {
        model.message.cloudProvenance = model.newCloudProvenance(references: [])
        model.message.cloudAuthorizationTargets = []
        model.recordCloudReads(targets, messageID: messageID)
      } else { model.recordArtifactReads(targets, messageID: messageID) }
      model.approvalAction = nil; model.approves = true; model.pluginPermitted = true
      model.hasMessage = true; model.pendingMailDraft = nil
    }
    reset()
    for cloud in [false, true] {
      reset(cloud: cloud)
      let current = model.artifactProvenance(for: model.message)
      precondition(model.artifactCreationIsCurrent(messageID: messageID, workspaceID: nil, provenance: current))
      model.gmailResultsCurrent = false
      precondition(!model.artifactCreationIsCurrent(messageID: messageID, workspaceID: nil, provenance: current))
      model.gmailResultsCurrent = true
    }
    reset()
    model.message.projectSourceReferences = [.init(id: source.id, projectID: projectID, fingerprint: AIRecordFingerprint.make(source)!)]
    let provenance = model.artifactProvenance(for: model.message)
    precondition(provenance.isValid && !provenance.isComplete && provenance.records.count == 4 && provenance.projectSources.count == 1)
    let citationTargets = model.answerCitationTargets(for: model.message)
    precondition(citationTargets.count == 5)
    for target in citationTargets {
      precondition(model.answerCitationTarget(for: AnswerSourceCitation.url(for: target), message: model.message) == target)
    }
    let forged = AnswerSourceCitation.url(for: .record(.person(UUID())))
    precondition(model.answerCitationTarget(for: forged, message: model.message) == nil)
    precondition(model.answerCitationTarget(for: URL(string: "memora-cite://1")!, message: model.message) == .record(.meeting(sharedID)))
    model.message.text = citationTargets.map { AnswerSourceCitation.marker(for: $0) }.joined(separator: "\n")
    let citedDocument = model.document(from: model.message)
    for target in citationTargets {
      precondition(model.documentCitationTarget(for: AnswerSourceCitation.url(for: target), document: citedDocument) == target)
    }
    precondition(model.documentCitationTarget(for: forged, document: citedDocument) == nil)

    // A stamped project source becomes unopenable once its text, project or
    // existence changes; a legacy document without a stamp stays a current link.
    let projectFileTarget = ArtifactSourceTarget.projectFile(source.id)
    let projectFileURL = AnswerSourceCitation.url(for: projectFileTarget)
    precondition(model.answerCitationTargets(for: model.message).contains(projectFileTarget))
    precondition(model.documentCitationTarget(for: projectFileURL, document: citedDocument) == projectFileTarget)
    model.projectSources[0].title = "更新後の資料"
    precondition(!model.answerCitationTargets(for: model.message).contains(projectFileTarget))
    precondition(model.documentCitationTarget(for: projectFileURL, document: citedDocument) == nil)
    model.projectSources = [source]
    model.projectSources[0].projectID = nil
    precondition(model.documentCitationTarget(for: projectFileURL, document: citedDocument) == nil)
    model.projectSources = [source]
    model.projectSources = []
    precondition(model.documentCitationTarget(for: projectFileURL, document: citedDocument) == nil)
    model.projectSources = [source]
    var unstampedDocument = citedDocument
    unstampedDocument.provenance = nil
    precondition(model.documentCitationTarget(for: projectFileURL, document: unstampedDocument) == projectFileTarget,
      "a document without a stamp links to the current source")
    model.projectSources = [source]
    var oldDocument = citedDocument
    oldDocument.provenance = nil; oldDocument.sourceRecordIDs = nil; oldDocument.sourceProjectFileIDs = nil
    precondition(model.documentCitationTarget(for: AnswerSourceCitation.url(for: .record(.person(sharedID))), document: oldDocument) == nil)
    precondition(model.documentCitationTarget(for: MeetingLink.url(for: sharedID)!, document: oldDocument) == .record(.meeting(sharedID)))
    let grants = model.message.cloudAuthorizationTargets
    model.openExternalSourceCitation(AnswerSourceCitation.url(for: .record(.person(sharedID))))
    precondition(model.pendingSourceCitation == .record(.person(sharedID)) && model.message.cloudAuthorizationTargets == grants)
    model.pendingSourceCitation = nil
    let rows = model.artifactSourceRows(provenance: provenance, meetingIDs: [sharedID, sharedID])
    precondition(rows.count == 5 && Set(rows.map(\.id)).count == 5)
    precondition(rows.allSatisfy { $0.canOpen && $0.hasChanged == false && $0.allowsCloudAI })
    let personTarget = ArtifactSourceTarget.record(.person(sharedID))
    precondition(rows.first { $0.target == personTarget }?.title == "架空の田中")
    model.people[0].note = "参照後に変更"
    precondition(model.artifactSourceRows(provenance: provenance).first { $0.target == personTarget }?.hasChanged == true)
    model.people[0].privacy.allowsCloudAI = false
    let revoked = model.artifactSourceRows(provenance: provenance).first { $0.target == personTarget }!
    precondition(revoked.canOpen && !revoked.allowsCloudAI && revoked.status.contains("変更あり") && revoked.status.contains("送信不可"))
    model.people.removeAll()
    let missing = model.artifactSourceRows(provenance: provenance).first { $0.target == personTarget }!
    precondition(!missing.canOpen && missing.title == "人物")
    precondition(model.artifactSourceRows(provenance: nil, meetingIDs: [sharedID]).first?.hasChanged == nil)
    model.currentTeamID = "another-workspace"
    precondition(model.artifactSourceRows(provenance: provenance).isEmpty && !model.canOpenArtifactSource(.record(.meeting(sharedID)), workspaceID: nil))
    precondition(model.answerCitationTargets(for: model.message).isEmpty)
    precondition(model.documentCitationTarget(for: MeetingLink.url(for: sharedID)!, document: citedDocument) == nil)
    model.openExternalSourceCitation(AnswerSourceCitation.url(for: .record(.task(sharedID))))
    precondition(model.pendingSourceCitation == nil && model.missingRecordNotice != nil)
    model.currentTeamID = nil
    model.isStoreProtected = true; precondition(model.artifactSourceRows(provenance: provenance).isEmpty)
    model.isStoreProtected = false; model.isRestoring = true
    precondition(!model.canOpenArtifactSource(.record(.task(sharedID)), workspaceID: nil))
    model.isRestoring = false
    var invalid = provenance
    invalid.records.append(invalid.records[0]); precondition(!invalid.isValid && model.artifactSourceRows(provenance: invalid).isEmpty)
    invalid = provenance; invalid.records[0].fingerprint = "untrusted"; precondition(!invalid.isValid)
    invalid = provenance; invalid.projectSources = Array(repeating: invalid.projectSources[0], count: 33); precondition(!invalid.isValid)
    invalid = provenance; invalid.workspaceID = String(repeating: "a", count: 257); precondition(!invalid.isValid)

    // Actual document/mail save paths preserve attribution when the author edits the output.
    reset(cloud: false)
    model.recordArtifactProjectSource(.init(id: source.id, projectID: projectID, fingerprint: AIRecordFingerprint.make(source)!), messageID: messageID)
    let local = model.artifactProvenance(for: model.message)
    precondition(local.records.count == 3 && !local.isComplete && model.message.cloudProvenance == nil)
    precondition(local.projectSources.count == 1 && model.message.projectSourceReferences.isEmpty)
    precondition(model.artifactCreationIsCurrent(messageID: messageID, workspaceID: nil, provenance: local))
    model.projectSources[0].projectID = nil
    precondition(!model.artifactCreationIsCurrent(messageID: messageID, workspaceID: nil, provenance: local))
    precondition(model.artifactSourceRows(provenance: local).last?.hasChanged == true)
    model.projectSources = [source]
    let document = model.document(from: model.message)
    precondition(document.provenance == local && model.addDocument(document))
    precondition(model.updateDocument(document.id, title: "編集した資料", body: "編集した本文"))
    precondition(model.document(id: document.id)?.provenance == local)
    model.rejectWrites = true
    let before = model.documents
    precondition(!model.addDocument(document) && model.documents == before)
    model.rejectWrites = false
    let call = AgentToolCall(id: "mail", name: "draft_email", arguments: ["to": [], "subject": "確認", "body": "確認をお願いします。"])
    let saved = await model.draftEmailTool(call, messageID: messageID)
    precondition(!saved.isError && model.mailDrafts.count == 1 && model.pendingMailDraft?.provenance == local && saved.dataChange == .committed)
    var draft = model.mailDrafts[0]
    draft.body = "本人が編集した本文"; precondition(model.saveMailDraft(draft))
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let documentBytes) = reopened.readOutcome("documents"),
          case .data(let mailBytes) = reopened.readOutcome("memora.mailDrafts.v1") else { preconditionFailure("missing SQLite artifacts") }
    let documents = try JSONDecoder().decode([MemoraDocument].self, from: documentBytes)
    let drafts = try JSONDecoder().decode([MailDraft].self, from: mailBytes)
    precondition(documents[0].provenance == local && drafts[0].provenance == local && drafts[0].status == .draft)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    legacy.removeValue(forKey: "provenance")
    let legacyDraft = try JSONDecoder().decode(MailDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyDraft.provenance == nil)
    legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
    legacy.removeValue(forKey: "provenance")
    let legacyDocument = try JSONDecoder().decode(MemoraDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyDocument.provenance == nil)
    draft.provenance = invalid; precondition(!model.saveMailDraft(draft))

    // Suspend the production draft tool at its approval boundary and mutate state there.
    model.mailDrafts = []
    for change in 0..<8 {
      reset(cloud: false)
      model.approvalAction = {
        await Task.yield()
        switch change {
        case 0: model.currentTeamID = "different"
        case 1: model.tasks[0].title += "変更"
        case 2: model.hasMessage = false
        case 3: model.pluginPermitted = false
        case 4: model.isStoreProtected = true
        case 5: model.isRestoring = true
        case 6: model.rejectWrites = true
        default: model.approves = false
        }
      }
      let result = await model.draftEmailTool(call, messageID: messageID)
      precondition((result.isError || change == 7) && model.mailDrafts.isEmpty && model.pendingMailDraft == nil)
      model.currentTeamID = nil; model.isStoreProtected = false; model.isRestoring = false; model.rejectWrites = false
    }
    model.people = [Person(id: sharedID, name: "架空の田中", contactIdentifier: nil, privacy: grant)]
    reset()
    model.approvalAction = { await Task.yield(); model.people[0].privacy.allowsCloudAI = false }
    let denied = await model.draftEmailTool(call, messageID: messageID)
    precondition(denied.isError && model.mailDrafts.isEmpty && denied.dataChange == .none)
    reset(cloud: false)
    model.approvalAction = { withUnsafeCurrentTask { $0?.cancel() } }
    let cancelled = Task { @MainActor in await model.draftEmailTool(call, messageID: messageID) }
    let result = await cancelled.value
    precondition(result.isError && model.mailDrafts.isEmpty)
    try await mockConversationScenario(root: root)
    try readOnlyDocumentChecks(root: root)
    #if INTELLIGENT_UI_CHECKS
    try await IntelligentUIContextChecks.run(root: root)
    #endif
    print("ArtifactProvenanceChecks: passed (typed collisions, capture, changes/revocation/deletion, workspace/protected/restore, legacy, production document/mail save/edit + real SQLite reopen, suspended draft approval/cancel/stale permissions; no network)")
  }

  @MainActor static func readOnlyDocumentChecks(root: URL) throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("read-only-documents.sqlite"))
    let document = MemoraDocument(title: "保持する資料", kind: .document, markdown: "元の本文")
    let slide = MemoraDocument(title: "保持するスライド", kind: .slides, slides: [.init(title: "概要", bullets: ["根拠"])])
    precondition(model.addDocument(document) && model.addDocument(slide))
    let original = model.documents
    guard case .data(let saved) = model.store.readOutcome("documents") else { preconditionFailure() }
    for mode in 0..<3 {
      model.currentTeamID = mode == 0 ? "read-only-team" : nil
      model.isRestoring = mode == 1
      model.isStoreProtected = mode == 2
      precondition(!model.addDocument(.init(title: "拒否する資料", kind: .document, markdown: "本文")))
      precondition(!model.updateDocument(document.id, title: "拒否する編集", body: "置換"))
      precondition(!model.updateDocumentSlides(slide.id, title: "拒否する編集", slides: [.init(title: "置換", bullets: [])], expectedUpdatedAt: slide.updatedAt))
      precondition(!model.deleteDocument(document.id))
      precondition(model.documents == original)
      guard case .data(let retained) = model.store.readOutcome("documents") else { preconditionFailure() }
      precondition(retained == saved)
    }
    model.currentTeamID = nil; model.isRestoring = false; model.isStoreProtected = false
    precondition(model.updateDocument(document.id, title: "個人では編集可能", body: "更新"))
    print("PASS: actual document mutators refuse team/restore/protected writes with SQLite bytes unchanged")
  }

  @MainActor static func mockConversationScenario(root: URL) async throws {
    let storeURL = root.appendingPathComponent("mock-conversation.sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    var grant = RecordPrivacy(classification: .personal); grant.allowsCloudAI = true
    let person = Person(id: UUID(), name: "田中", note: "架空の提案相談", contactIdentifier: nil, privacy: grant)
    model.people = [person, Person(id: UUID(), name: "田中", note: "別人の非公開情報", contactIdentifier: nil)]
    let task = MemoraTask(id: UUID(), title: "見積もりを確認する", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: grant)
    let journal = LifeLogEntry(id: UUID(), createdAt: .now, title: "相談メモ", summary: "次回確認する", source: .iphone, privacy: grant, personIDs: [person.id])
    model.tasks = [task]; model.lifeLogEntries = [journal]
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    let messageID = model.message.id
    let personMarker = AnswerSourceCitation.marker(for: .record(.person(person.id)))
    let taskMarker = AnswerSourceCitation.marker(for: .record(.task(task.id)))
    let journalMarker = AnswerSourceCitation.marker(for: .record(.journal(journal.id)))
    let answer = "田中さんとの確認事項です。\(personMarker)\n\n見積もりを確認します。\(taskMarker)\n\n相談メモも参照しています。\(journalMarker)"
    let read = AgentToolCall(id: "mock-read-person", name: "read_person", arguments: ["person_id": person.id.uuidString])
    let draft = AgentToolCall(id: "mock-draft", name: "draft_email", arguments: ["to": [], "subject": "ご相談の確認", "body": "見積もりを確認します。" + taskMarker])
    var turns = [AgentTurn(text: "", toolCalls: [read]), AgentTurn(text: "", toolCalls: [draft]), AgentTurn(text: answer, toolCalls: [])]
    var outcomes: [AgentToolOutcome] = []
    let result = await AgentConversationLoop.run(isAuthorized: { model.isCloudSessionAuthorized(messageID) },
      next: { turns.removeFirst() }, execute: { call in
        if call.name == "read_person" { return model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI) }
        return await model.draftEmailTool(call, messageID: messageID)
      }, accept: { _, batch in outcomes += batch.map(\.outcome) })
    precondition(result.text == answer && outcomes.count == 2 && outcomes.allSatisfy { !$0.isError })
    precondition(outcomes[0].text.contains(personMarker) && outcomes[0].text.contains(taskMarker) && outcomes[0].text.contains(journalMarker))
    precondition(!outcomes[0].text.contains("別人の非公開情報"))
    model.message.text = answer
    let document = model.document(from: model.message)
    precondition(model.addDocument(document) && model.mailDrafts.count == 1 && model.mailDrafts[0].recipients.isEmpty)
    precondition(!model.mailDrafts[0].body.contains("【タスク:"))
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let docData) = reopened.readOutcome("documents"), case .data(let draftData) = reopened.readOutcome("memora.mailDrafts.v1") else { preconditionFailure() }
    let storedDocument = try JSONDecoder().decode([MemoraDocument].self, from: docData)[0]
    let storedDraft = try JSONDecoder().decode([MailDraft].self, from: draftData)[0]
    precondition(storedDraft.status == .draft && storedDraft.provenance?.records.count == 3)
    for target in model.answerCitationTargets(for: model.message) {
      let url = AnswerSourceCitation.url(for: target)
      precondition(storedDocument.markdown.contains(url.absoluteString))
      precondition(model.documentCitationTarget(for: url, document: storedDocument) == target)
    }
    let savedProvenance = model.message.cloudProvenance
    let revoked = await AgentConversationLoop.run(isAuthorized: { model.isCloudSessionAuthorized(messageID) },
      next: { model.people[0].privacy.allowsCloudAI = false; return AgentTurn(text: "失効後の回答", toolCalls: [draft]) },
      execute: { _ in preconditionFailure("revoked draft executed") }, accept: { _, _ in preconditionFailure("revoked turn accepted") })
    guard case .failure(.contextChanged) = revoked else { preconditionFailure("revocation ignored") }
    precondition(!model.canReuseCloudConversation(savedProvenance) && model.mailDrafts.count == 1)
    precondition(model.canOpenArtifactSource(.record(.person(person.id)), workspaceID: nil))
    print("Mock person-to-answer/document/mail scenario: passed (production loop/domain/builder/SQLite, mocked provider and approval/registry entry points, explicit duplicate person ID, typed citations, retained draft, mid-turn revoke; no network)")
  }
}
