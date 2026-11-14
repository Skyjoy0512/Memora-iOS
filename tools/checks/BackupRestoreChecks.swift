import Foundation
import SQLite3
import Darwin

@main
struct BackupRestoreChecks {
  static func manifestBounds(in package: URL, originalJSON: Data, meeting: Meeting, exportRoot: URL) throws {
    let file = package.appendingPathComponent(BackupPackage.manifestName)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(BackupPackage.maximumManifestBytes + 1))
    try handle.close()
    do { _ = try BackupPackage.read(from: package); preconditionFailure("Oversized manifest was loaded") }
    catch BackupPackage.BackupError.manifestTooLarge {}
    try originalJSON.write(to: file, options: .atomic)
    let boundary = package.appendingPathComponent("bounded.bin")
    for size in [31, 32, 33] {
      let bytes = Data(repeating: 0x20, count: size)
      try bytes.write(to: boundary, options: .atomic)
      if size <= 32 {
        let read = try BackupPackageFile.read("bounded.bin", in: package, maximumBytes: 32)
        precondition(read == bytes)
      } else {
        do { _ = try BackupPackageFile.read("bounded.bin", in: package, maximumBytes: 32); preconditionFailure() }
        catch BackupPackage.BackupError.manifestTooLarge {}
      }
    }
    let fifo = package.appendingPathComponent("pipe.bin")
    precondition(mkfifo(fifo.path, 0o600) == 0)
    do { _ = try BackupPackageFile.read("pipe.bin", in: package, maximumBytes: 32); preconditionFailure() }
    catch BackupPackage.BackupError.unreadable {}
    try FileManager.default.removeItem(at: fifo)
    let link = package.appendingPathComponent("link.bin")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: boundary)
    do { _ = try BackupPackageFile.read("link.bin", in: package, maximumBytes: 32); preconditionFailure() }
    catch BackupPackage.BackupError.unreadable {}
    try FileManager.default.removeItem(at: link)
    try FileManager.default.removeItem(at: boundary)
    let existing = try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).sorted()
    var huge = meeting
    huge.notes = String(repeating: "x", count: BackupPackage.maximumManifestBytes + 1)
    do {
      _ = try BackupPackage.write(meetings: [huge], spaces: [], tasks: [], lifeLogEntries: [], people: [], aiHistory: [], into: exportRoot)
      preconditionFailure("Exporter made a package the reader cannot accept")
    } catch BackupPackage.BackupError.manifestTooLarge {}
    let remaining = try FileManager.default.contentsOfDirectory(atPath: exportRoot.path).sorted()
    let preserved = try Data(contentsOf: file)
    precondition(remaining == existing && preserved == originalJSON)
    print("PASS backup manifest: sparse 64 MiB+1 refusal, exact small reader boundary, FIFO/symlink refusal, oversized export cleanup and original package preservation")
  }

  enum FixtureFailure: Error { case rejected }

  @MainActor static func main() async throws {
    let fm = FileManager.default
    try fm.createDirectory(at: FixtureFiles.root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: FixtureFiles.root) }
    let input = FixtureFiles.root.appendingPathComponent("input")
    try fm.createDirectory(at: input, withIntermediateDirectories: true)
    try fm.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    try fm.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    try fm.createDirectory(at: MediaFiles.photosDirectory, withIntermediateDirectories: true)
    try await TeamSharePackageChecks.run()

    let docx = try Data(contentsOf: URL(fileURLWithPath: "docs/fixtures/ask-ai-artifacts/generated.docx"))
    let pptx = try Data(contentsOf: URL(fileURLWithPath: "docs/fixtures/ask-ai-artifacts/generated.pptx"))
    let audio = Data("fixture audio, never played".utf8)
    let photo = Data("fixture image, never displayed".utf8)
    let workspaceFiles = ["template.docx": docx, "template.pptx": pptx, "artifact.pptx": pptx, "older.pptx": pptx, "source.txt": Data("根拠の本文".utf8)]
    for (name, data) in workspaceFiles { try data.write(to: ProjectSourceFiles.resolve(name)!) }
    try audio.write(to: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    try photo.write(to: MediaFiles.photosDirectory.appendingPathComponent("photo.jpg"))
    var meeting = Meeting(id: UUID(), title: "Fixture", createdAt: .now, duration: 1, source: .recording,
      status: .ready, summary: "Fixture summary", keyPoints: [], decisions: [], openQuestions: [], transcript: [],
      spaceID: nil, audioURL: MediaFiles.resolve("audio.m4a"))
    meeting.photoFileNames = ["photo.jpg"]
    let segment = TranscriptSegment(id: UUID(), speaker: "話者1", speakerIsCertain: true, timestamp: 0,
      text: "担当者は次回の確認後に決めます。")
    meeting.transcript = [segment]
    let version = TemplateSummary.snapshot(record: meeting, templateID: "market.regular",
      preferences: SummaryPreferences(), modelInfo: "backup fixture",
      knowledge: .init(selectedProfileIDs: ["market.regular"], facts: [
        .init(id: "f1", category: .owner, content: segment.text, status: .pending,
          sourceReferences: [.init(sourceSegmentID: segment.id.uuidString, quote: segment.text)], origin: .user)
      ], coverage: [.init(aspect: "予算", status: .notMentioned)]), reconciledUserEdits: true)
    meeting.summaryVersions = [version]
    meeting.activeSummaryVersionID = version.id

    let project = MemoraSpace()
    let person = Person(id: UUID(), name: "検証用の人物", note: nil, contactIdentifier: nil)
    let now = Date.now
    var memory = AIMemory(id: UUID(), text: "簡潔な文章を好む", origin: .told, createdAt: now,
      semantic: .init(type: .style, value: "簡潔な文章を好む", sourceReference: "settings", observedAt: now, updatedAt: now, validFrom: now))
    memory = memory.edited(text: "結論から簡潔に書く", status: .current, kind: .style, sensitivity: .standard, predicate: "文章", workspaceID: nil)
    var draft = MailDraft(recipients: [], subject: "会議のフォローアップ", body: "決定事項を共有します。", cc: ["fixture@example.com"])
    draft.personIDs = [person.id]; draft.projectID = project.id; draft.recordIDs = [meeting.id]
    let template = CompanyTemplate(name: "会社書式", format: .docx, fileReference: "template.docx", projectID: project.id,
      analysis: try CompanyTemplateEngine.analyze(docx, format: .docx))
    let powerpointTemplate = CompanyTemplate(name: "PowerPointの計測", format: .pptx, fileReference: "template.pptx", projectID: project.id,
      analysis: try CompanyTemplateEngine.analyze(pptx, format: .pptx))
    var document = MemoraDocument(title: "提案資料", kind: .slides, slides: [DocumentSlide(title: "概要", bullets: ["架空の内容"])], spaceID: project.id)
    document.artifactFileReference = "artifact.pptx"; document.artifactFormat = "PPTX"
    document.contentRevision = 2; document.artifactRevision = 1
    document.companyTemplateID = powerpointTemplate.id; document.companyTemplateVersion = powerpointTemplate.version
    document.artifactHistory = [.init(fileReference: "older.pptx", format: .pptx, contentRevision: 0,
      companyTemplateID: powerpointTemplate.id, companyTemplateVersion: powerpointTemplate.version)]
    document.presentationPlan = PresentationPlan(purpose: "判断を支援", audience: "会議の参加者", decision: "次の確認事項",
      assumptions: ["架空データ"], storyline: [.init(slideID: document.slides[0].id, claim: "概要を共有する", evidence: ["会議"], unconfirmed: ["実機検証"])])
    document.sourceRecordIDs = [meeting.id]
    var source = ProjectSource(projectID: project.id, kind: .note, title: "根拠", extractedTextReference: "source.txt")
    let attachment = ProjectSource(projectID: project.id, kind: .pdf, title: "添付", extractedTextReference: "source.txt")
    source.attachedSourceIDs = [attachment.id]
    let artifactProvenance = ArtifactProvenance(sourceMessageID: UUID(), records: [
      .init(target: .person(person.id), fingerprint: String(repeating: "a", count: 64)),
      .init(target: .journal(UUID()), fingerprint: String(repeating: "b", count: 64)),
      .init(target: .task(UUID()), fingerprint: String(repeating: "c", count: 64))],
      projectSources: [.init(id: source.id, projectID: project.id, fingerprint: String(repeating: "d", count: 64))])
    document.provenance = artifactProvenance; draft.provenance = artifactProvenance
    let sessionID = UUID()
    let episode = AIEpisode(id: UUID(), sessionID: sessionID, date: now, topic: "提案書", objective: "資料作成", summary: "会社書式を確認した", personIDs: [person.id], projectIDs: [project.id], recordIDs: [meeting.id], documentIDs: [document.id])
    let history = AIConversationEntry(id: UUID(), question: "前回の提案書", answer: "保存しました", scopeLabel: "すべて", createdAt: now, episode: episode)
    var skill = MemoraSkill.breadthSkills[0]
    skill.id = "custom-" + UUID().uuidString
    let package = try BackupPackage.write(meetings: [meeting], spaces: [project], tasks: [], lifeLogEntries: [], people: [person], aiHistory: [history], aiMemories: [memory], mailDrafts: [draft], companyTemplates: [template, powerpointTemplate], documents: [document], projectSources: [source, attachment], customSkills: [skill], into: input)
    let summaryRoundtrip = try BackupPackage.read(from: package).meetings[0]
    precondition(summaryRoundtrip.summaryVersions == meeting.summaryVersions)
    precondition(summaryRoundtrip.activeSummaryVersionID == version.id)
    precondition(summaryRoundtrip.summaryVersions[0].sourceFingerprint == SummaryEvidence.fingerprint([segment]))

    let manifest = try BackupPackage.read(from: package)
    precondition(manifest.aiMemories == [memory] && manifest.mailDrafts == [draft] && manifest.companyTemplates == [template, powerpointTemplate])
    precondition(manifest.documents == [document] && manifest.aiHistory.first?.episode == episode)
    precondition(manifest.customSkills?.first?.category == skill.category)
    precondition(manifest.customSkills?.first?.examplePrompts == skill.examplePrompts)
    precondition(manifest.customSkills?.first?.outputDescription == skill.outputDescription)
    precondition(manifest.projectSources?.first { $0.id == source.id }?.attachedSourceIDs == [attachment.id],
      "attachment link must survive the backup manifest")
    for (name, bytes) in workspaceFiles {
      let restored = try Data(contentsOf: package.appendingPathComponent("workspace/" + name))
      precondition(restored == bytes)
    }
    let manifestURL = package.appendingPathComponent(BackupPackage.manifestName)
    let originalJSON = try Data(contentsOf: manifestURL)
    try manifestBounds(in: package, originalJSON: originalJSON, meeting: meeting, exportRoot: input)
    var json = try JSONSerialization.jsonObject(with: originalJSON) as! [String: Any]
    for key in ["aiMemories", "mailDrafts", "companyTemplates", "documents", "projectSources", "projectChats", "customSkills", "skillSelections", "webResearchReports"] { json.removeValue(forKey: key) }
    json["version"] = 1
    var oldHistory = json["aiHistory"] as! [[String: Any]]
    for index in oldHistory.indices { oldHistory[index].removeValue(forKey: "episode") }
    json["aiHistory"] = oldHistory
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)
    let legacy = try BackupPackage.read(from: package)
    precondition(legacy.aiMemories == nil && legacy.mailDrafts == nil && legacy.companyTemplates == nil && legacy.documents == nil && legacy.aiHistory.first?.episode == nil)
    try originalJSON.write(to: manifestURL, options: .atomic)

    var invalid = manifest
    invalid.companyTemplates?[1].analysis.presentation?.widthEMU = -1
    try reject(invalid, in: package)
    invalid = manifest; invalid.companyTemplates?[1].analysis.presentation?.masters.append(powerpointTemplate.analysis.presentation!.masters[0])
    try reject(invalid, in: package)
    invalid = manifest
    invalid.documents = [document, document]
    try reject(invalid, in: package)
    invalid = manifest; invalid.mailDrafts?[0].recipients = Array(repeating: "fixture@example.com", count: 101)
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactFileReference = "../escape.pptx"
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].contentRevision = -1
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactRevision = 3
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].companyTemplateVersion = 0
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].companyTemplateID = nil
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactHistory?[0].fileReference = "../older.pptx"
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactHistory?.append(document.artifactHistory![0])
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].artifactHistory?[0].contentRevision = 3
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].presentationPlan?.storyline[0].slideID = UUID()
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].presentationPlan?.assumptions = Array(repeating: "過大入力", count: 21)
    try reject(invalid, in: package)
    invalid = manifest; invalid.documents?[0].provenance?.records.append(artifactProvenance.records[0])
    try reject(invalid, in: package)
    invalid = manifest; invalid.mailDrafts?[0].provenance?.workspaceID = "foreign"
    try reject(invalid, in: package)
    try originalJSON.write(to: manifestURL, options: .atomic)

    // A valid leaf beneath a linked directory must not be accepted as package data.
    let folder = package.appendingPathComponent("workspace")
    let moved = package.appendingPathComponent("held-workspace")
    try fm.moveItem(at: folder, to: moved)
    try fm.createSymbolicLink(at: folder, withDestinationURL: moved)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: folder); try fm.moveItem(at: moved, to: folder)
    let heldManifest = package.appendingPathComponent("held-manifest")
    try fm.moveItem(at: manifestURL, to: heldManifest)
    try fm.createSymbolicLink(at: manifestURL, withDestinationURL: heldManifest)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: manifestURL); try fm.moveItem(at: heldManifest, to: manifestURL)

    try Data("{broken".utf8).write(to: manifestURL, options: .atomic)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try originalJSON.write(to: manifestURL, options: .atomic)
    let artifactURL = folder.appendingPathComponent("artifact.pptx")
    try fm.removeItem(at: artifactURL)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try pptx.write(to: artifactURL)
    let historicalURL = folder.appendingPathComponent("older.pptx")
    try fm.removeItem(at: historicalURL)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try pptx.write(to: historicalURL)
    let largeURL = folder.appendingPathComponent("oversize.docx")
    fm.createFile(atPath: largeURL.path, contents: nil)
    let largeHandle = try FileHandle(forWritingTo: largeURL)
    try largeHandle.truncate(atOffset: UInt64(ProjectSourceFiles.maximumFileBytes + 1)); try largeHandle.close()
    invalid = manifest; invalid.documents?[0].artifactFileReference = "oversize.docx"
    try reject(invalid, in: package)
    try fm.removeItem(at: largeURL)
    let mediaFolder = package.appendingPathComponent("media")
    let heldMedia = package.appendingPathComponent("held-media")
    try fm.moveItem(at: mediaFolder, to: heldMedia)
    try fm.createSymbolicLink(at: mediaFolder, withDestinationURL: heldMedia)
    try expectFailure { _ = try BackupPackage.read(from: package) }
    try fm.removeItem(at: mediaFolder); try fm.moveItem(at: heldMedia, to: mediaFolder)

    // Clear only this isolated destination, simulating a fresh app container.
    for name in workspaceFiles.keys { try fm.removeItem(at: ProjectSourceFiles.resolve(name)!) }
    try fm.removeItem(at: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    try fm.removeItem(at: MediaFiles.photosDirectory.appendingPathComponent("photo.jpg"))
    // Actually restore the pre-feature package, rather than only decoding its JSON.
    try JSONSerialization.data(withJSONObject: json).write(to: manifestURL, options: .atomic)
    var legacyCommitted = false
    try await BackupRestoreTransaction.restore(from: package) { value in
      precondition(value.aiMemories == nil && value.companyTemplates == nil && value.mailDrafts == nil)
      precondition(value.projectSources == nil, "older packages without sources must decode as absent")
      legacyCommitted = true
    }
    precondition(legacyCommitted)
    let legacyAudio = try Data(contentsOf: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    precondition(legacyAudio == audio)
    BackupPackage.removeInstalledMedia([("audio.m4a", true), ("photo.jpg", false)])
    try originalJSON.write(to: manifestURL, options: .atomic)
    precondition(emptyDestinations())

    let storeURL = FixtureFiles.root.appendingPathComponent("records.sqlite")
    let store = LocalStore(fileURL: storeURL)
    try store.prepare()
    try store.write("unrelated", data: Data("keep".utf8))
    var db: OpaquePointer?
    precondition(sqlite3_open(storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_fixture BEFORE INSERT ON documents WHEN NEW.key = 'mail' BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    do {
      try await BackupRestoreTransaction.restore(from: package) { value in
        try store.applyBatch(writes: try writes(value), removing: [])
      }
      preconditionFailure("SQLite failure was reported as success")
    } catch {}
    precondition(emptyDestinations())
    if case .missing = store.readOutcome("memories") {} else { preconditionFailure("Partial records committed") }
    if case .data(let bytes) = store.readOutcome("unrelated") { precondition(bytes == Data("keep".utf8)) } else { preconditionFailure() }
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_fixture;", nil, nil, nil) == SQLITE_OK)

    do {
      try await BackupRestoreTransaction.restore(from: package) { _ in throw FixtureFailure.rejected }
      preconditionFailure("Changed workspace/record gate accepted")
    } catch FixtureFailure.rejected {}
    precondition(emptyDestinations())
    let cancelled = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Cancelled restore committed") }
    }
    do { try await cancelled.value; preconditionFailure("Cancellation ignored") } catch is CancellationError {}
    precondition(emptyDestinations())

    // Hold the main actor until preparation has installed files. A cancelled parent
    // must roll them back before its commit callback can run.
    var preparationStarted = false
    let stagedCancellation = Task { @MainActor in
      preparationStarted = true
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Cancelled prepared restore committed") }
    }
    while !preparationStarted { await Task.yield() }
    let deadline = Date().addingTimeInterval(5)
    while !fm.fileExists(atPath: ProjectSourceFiles.resolve("template.docx")!.path) && Date() < deadline { usleep(1_000) }
    precondition(fm.fileExists(atPath: ProjectSourceFiles.resolve("template.docx")!.path), "Preparation never reached its suspended commit")
    stagedCancellation.cancel()
    do { try await stagedCancellation.value; preconditionFailure("Prepared cancellation ignored") } catch is CancellationError {}
    precondition(emptyDestinations())

    // Sorted installation encounters a later conflict; earlier copies must be taken back.
    let conflict = ProjectSourceFiles.resolve("template.docx")!
    try Data("existing bytes".utf8).write(to: conflict)
    do {
      try await BackupRestoreTransaction.restore(from: package) { _ in preconditionFailure("Conflict committed") }
      preconditionFailure("Conflict ignored")
    } catch BackupPackage.BackupError.mediaConflict {}
    let existing = try Data(contentsOf: conflict)
    precondition(existing == Data("existing bytes".utf8))
    precondition(!fm.fileExists(atPath: ProjectSourceFiles.resolve("artifact.pptx")!.path))
    precondition(!fm.fileExists(atPath: MediaFiles.directory.appendingPathComponent("audio.m4a").path))
    try fm.removeItem(at: conflict)

    try await BackupRestoreTransaction.restore(from: package) { value in
      try store.applyBatch(writes: try writes(value), removing: [])
    }
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    let memories = try JSONDecoder().decode([AIMemory].self, from: read(reopened, "memories"))
    let drafts = try JSONDecoder().decode([MailDraft].self, from: read(reopened, "mail"))
    let templates = try JSONDecoder().decode([CompanyTemplate].self, from: read(reopened, "templates"))
    let documents = try JSONDecoder().decode([MemoraDocument].self, from: read(reopened, "documents"))
    precondition(memories == [memory] && drafts == [draft] && templates == [template, powerpointTemplate] && documents == [document])
    for (name, bytes) in workspaceFiles {
      let restored = try Data(contentsOf: ProjectSourceFiles.resolve(name)!)
      precondition(restored == bytes)
    }
    let restoredAudio = try Data(contentsOf: MediaFiles.directory.appendingPathComponent("audio.m4a"))
    precondition(restoredAudio == audio)
    try checkSegmentOriginals(meeting, into: input)
    print("BackupRestoreChecks: passed (production package/restore + real SQLite, new metadata/files roundtrip, legacy restore, duplicate documents, recipient limits, truncated/missing/oversize, traversal/symlinks, DB rollback, cancellation/gate, conflict preserves bytes, reopen; isolated fixtures only)")
  }

  static func checkSegmentOriginals(_ original: Meeting, into input: URL) throws {
    let fm = FileManager.default
    var meeting = original
    meeting.photoFileNames = nil
    meeting.originalAudioFileNames = ["part-0.m4a", "part-1.m4a", "part-0.m4a"]
    meeting.recordingAudioManifest = .init(recordingID: meeting.id, sampleRate: 44_100, parts: [
      .init(fileName: "part-0.m4a", frameOffset: 0, frameCount: 44_100, state: .finalized),
      .init(fileName: "part-1.m4a", frameOffset: 44_100, frameCount: 44_100, state: .finalized)
    ])
    let parts = ["part-0.m4a": Data("original zero".utf8), "part-1.m4a": Data("original one".utf8)]
    for (name, bytes) in parts { try bytes.write(to: MediaFiles.resolve(name)!) }
    let package = try BackupPackage.write(meetings: [meeting], spaces: [], tasks: [], lifeLogEntries: [], people: [], aiHistory: [], into: input)
    let manifest = try BackupPackage.read(from: package)
    precondition(manifest.version == 3 && Set(manifest.audioFileNames) == ["audio.m4a", "part-0.m4a", "part-1.m4a"])
    precondition(manifest.meetings[0].originalAudioFileNames == meeting.originalAudioFileNames)
    precondition(manifest.meetings[0].recordingAudioManifest == meeting.recordingAudioManifest)
    var invalid = manifest
    invalid.version = 2
    try reject(invalid, in: package)
    invalid = manifest; invalid.audioFileNames.removeAll { $0 == "part-1.m4a" }
    try reject(invalid, in: package)
    invalid = manifest; invalid.meetings[0].originalAudioFileNames = ["../escape.m4a"]
    try reject(invalid, in: package)
    invalid = manifest; invalid.meetings[0].recordingAudioManifest?.recordingID = UUID()
    try reject(invalid, in: package)
    invalid = manifest; invalid.meetings[0].recordingAudioManifest?.parts[1].frameOffset += 1
    try reject(invalid, in: package)
    for name in ["../escape.m4a", "/tmp/escape.m4a", "missing.m4a"] {
      var invalidMeeting = meeting
      invalidMeeting.recordingAudioManifest = nil
      invalidMeeting.originalAudioFileNames = [name]
      try expectFailure {
        _ = try BackupPackage.write(meetings: [invalidMeeting], spaces: [], tasks: [], lifeLogEntries: [], people: [], aiHistory: [], into: input)
      }
    }
    let link = MediaFiles.resolve("part-link.m4a")!
    var missingPrimary = meeting
    missingPrimary.audioURL = nil
    missingPrimary.rawAudioReference = MediaFiles.directory.appendingPathComponent("missing-primary.m4a").path
    missingPrimary.originalAudioFileNames = []
    missingPrimary.recordingAudioManifest = nil
    do {
      _ = try BackupPackage.write(meetings: [missingPrimary], spaces: [], tasks: [], lifeLogEntries: [], people: [], aiHistory: [], into: input)
      preconditionFailure("Unresolved original reference silently omitted")
    } catch BackupPackage.BackupError.missingSource(let names) {
      precondition(names == ["missing-primary.m4a"])
    }
    try fm.createSymbolicLink(at: link, withDestinationURL: MediaFiles.resolve("part-0.m4a")!)
    var linked = meeting; linked.originalAudioFileNames = ["part-link.m4a"]; linked.recordingAudioManifest = nil
    try expectFailure { _ = try BackupPackage.write(meetings: [linked], spaces: [], tasks: [], lifeLogEntries: [], people: [], aiHistory: [], into: input) }
    try fm.removeItem(at: link)
    for name in manifest.audioFileNames { try fm.removeItem(at: MediaFiles.resolve(name)!) }
    let installed = try BackupPackage.install(mediaFrom: package, manifest: manifest)
    for (name, bytes) in parts {
      let restored = try Data(contentsOf: MediaFiles.resolve(name)!)
      precondition(restored == bytes)
    }
    precondition(installed.count == 3)
    BackupPackage.removeInstalledMedia(installed)
    print("PASS: v3 original audio package roundtrip/install, deduplication, missing/unsafe/link originals refused; v1/v2 remain supported")
  }

  static func writes(_ value: BackupPackage.Manifest) throws -> [(key: String, data: Data)] {
    [("memories", try JSONEncoder().encode(value.aiMemories)), ("mail", try JSONEncoder().encode(value.mailDrafts)),
     ("templates", try JSONEncoder().encode(value.companyTemplates)), ("documents", try JSONEncoder().encode(value.documents))]
  }
  static func read(_ store: LocalStore, _ key: String) -> Data {
    guard case .data(let data) = store.readOutcome(key) else { preconditionFailure("Missing restored key") }; return data
  }
  static func reject(_ manifest: BackupPackage.Manifest, in package: URL) throws {
    let url = package.appendingPathComponent(BackupPackage.manifestName)
    let original = try Data(contentsOf: url)
    defer { try? original.write(to: url, options: .atomic) }
    try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
    try expectFailure { _ = try BackupPackage.read(from: package) }
  }
  static func expectFailure(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    preconditionFailure("Invalid backup accepted")
  }
  static func emptyDestinations() -> Bool {
    [ProjectSourceFiles.directory, MediaFiles.directory, MediaFiles.photosDirectory].allSatisfy {
      ((try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []).isEmpty
    }
  }
}

// Unrelated record shapes, summary UI helpers and container locations are fixtures.
// Meeting codecs, package validation, installation, cancellation and SQLite are production.
enum FixtureFiles { static let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraBackupChecks-\(UUID())") }
enum SummaryPreviewCache { static func preview(for id: UUID, summary: String, build: (String) -> String) -> String { build(summary) } }
enum MarkdownBlockParser {
  static func hasBlockStructure(_ text: String) -> Bool { false }
  static func overview(of text: String) -> String { text }
}
struct MemoraSpace: Hashable, Codable { var id = UUID() }
struct MemoraTask: Hashable, Codable { var id = UUID(); var meetingID: UUID?; var title = "共有タスク" }
struct LifeLogEntry: Hashable, Codable {
  var id = UUID()
  var photoFileName: String?
  var meetingID: UUID?
  var latitude: Double?
  var longitude: Double?
  var locationName: String?
  var personIDs: [UUID] = []
}
struct ProjectChatThread: Codable { var id = UUID(); var projectID: UUID? }
enum MediaFiles {
  static var directory: URL { FixtureFiles.root.appendingPathComponent("audio") }
  static var photosDirectory: URL { FixtureFiles.root.appendingPathComponent("photos") }
  static func isPlainName(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0") }
  static func reference(for url: URL) -> String? { isPlainName(url.lastPathComponent) && url.deletingLastPathComponent() == directory ? url.lastPathComponent : nil }
  static func resolve(_ name: String) -> URL? { isPlainName(name) ? directory.appendingPathComponent(name) : nil }
  static func photoURL(_ name: String) -> URL? { isPlainName(name) ? photosDirectory.appendingPathComponent(name) : nil }
  static func requiredPhotoFiles(for name: String) -> [String] { [name] }
  static func regenerablePhotoFiles(for name: String) -> [String] { [] }
  static var permitsFixturePhotoWrite = false
  static func writePhoto(_ data: Data) -> String? {
    precondition(permitsFixturePhotoWrite, "No photo migration during backup read")
    let name = "migrated-\(UUID()).jpg"
    do { try data.write(to: photosDirectory.appendingPathComponent(name)); return name }
    catch { return nil }
  }
  @discardableResult static func deletePhoto(_ name: String) -> Bool { preconditionFailure("No photo migration during backup read") }
}
enum ProjectSourceFiles {
  static var directory: URL { FixtureFiles.root.appendingPathComponent("workspace") }
  static let maximumFileBytes = 50 * 1024 * 1024
  static let maximumStorageBytes = 500 * 1024 * 1024
  enum Failure: Error { case capacity }
  static func resolve(_ name: String) -> URL? { MediaFiles.isPlainName(name) ? directory.appendingPathComponent(name) : nil }
}
