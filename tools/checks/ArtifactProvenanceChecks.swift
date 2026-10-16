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
    model.message.projectSourceReferences = [.init(id: source.id, projectID: projectID, fingerprint: AIRecordFingerprint.make(source)!)]
    let provenance = model.artifactProvenance(for: model.message)
    precondition(provenance.isValid && !provenance.isComplete && provenance.records.count == 4 && provenance.projectSources.count == 1)
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
    precondition(!saved.isError && model.mailDrafts.count == 1 && model.pendingMailDraft?.provenance == local)
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
    precondition(denied.isError && model.mailDrafts.isEmpty)
    reset(cloud: false)
    model.approvalAction = { withUnsafeCurrentTask { $0?.cancel() } }
    let cancelled = Task { @MainActor in await model.draftEmailTool(call, messageID: messageID) }
    let result = await cancelled.value
    precondition(result.isError && model.mailDrafts.isEmpty)
    print("ArtifactProvenanceChecks: passed (typed collisions, capture, changes/revocation/deletion, workspace/protected/restore, legacy, production document/mail save/edit + real SQLite reopen, suspended draft approval/cancel/stale permissions; no network)")
  }
}
