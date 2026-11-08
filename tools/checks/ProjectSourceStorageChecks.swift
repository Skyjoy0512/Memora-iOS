import Foundation
import SQLite3

@main
struct ProjectSourceStorageChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let project = MemoraSpace(id: UUID(), name: "架空の保存先", symbol: "folder")
    try draftReads(root: root)
    try linkDraftCommit(root: root, project: project)
    try failedLinkRetry(root: root, project: project)
    try await noteDraftCommit(root: root, project: project)
    let model = try MemoraModel(storeURL: root.appendingPathComponent("sources.sqlite"))
    model.spaces = [project]
    guard let id = try await model.addProjectNote(title: "元のタイトル", text: "保存した本文", projectID: project.id),
          let original = model.source(id: id), let originalName = original.extractedTextReference else { preconditionFailure("Note was not saved") }
    precondition(original.processingStatus == .ready && original.textCoverage == .complete && !original.privacy.allowsCloudAI)
    expect(try text(original) == "保存した本文")
    expect(try reload(model) == [original])
    expect(try await model.updateProjectNote(id, title: "再編集", text: "更新した本文"))
    let edited = model.source(id: id)!
    precondition(edited.title == "再編集" && edited.extractedTextReference != originalName)
    precondition(!FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(originalName)!.path))
    expect(try text(edited) == "更新した本文" && reload(model) == [edited])
    precondition(model.invalidated.contains(.source(id)))

    // A legacy source may share a file reference. Editing one never deletes the
    // other's only copy, even though both records have different source IDs.
    var shared = edited
    shared.id = UUID()
    precondition(model.storeProjectSource(shared))
    expect(try await model.updateProjectNote(id, title: "独立した更新", text: "片方だけ変更"))
    expect(try text(shared) == "更新した本文")
    let previousCount = model.projectSources.count
    async let first = model.addProjectNote(title: "並行追加1", text: "本文1", projectID: project.id)
    async let second = model.addProjectNote(title: "並行追加2", text: "本文2", projectID: project.id)
    let additions = try await (first, second)
    precondition(additions.0 != nil && additions.1 != nil && additions.0 != additions.1)
    precondition(model.projectSources.count == previousCount + 2)
    expect(try reload(model) == model.projectSources)

    for edit in [false, true] {
      for mode in 0..<12 { try await race(root: root, edit: edit, mode: mode, project: project) }
    }
    for edit in [false, true] {
      for local in [false, true] { try await rollback(root: root, edit: edit, local: local, project: project) }
    }
    let filesBefore = try files()
    model.currentTeamID = "not-connected"
    precondition(!model.storeProjectSource(edited))
    expect(try await model.addProjectNote(title: "", text: "拒否される本文", projectID: project.id) == nil)
    expect(try await !model.updateProjectNote(id, title: "拒否", text: "拒否される本文"))
    expect(try files() == filesBefore)
    model.currentTeamID = nil
    do {
      _ = try await model.addProjectNote(title: "", text: String(repeating: "a", count: 512 * 1_024 + 1), projectID: project.id)
      preconditionFailure("Oversized note accepted")
    } catch ProjectSourceFiles.Failure.noteTooLarge {}
    do {
      _ = try await model.addProjectNote(title: "", text: String(repeating: "\u{1}", count: 400_000), projectID: project.id)
      preconditionFailure("Unreadable JSON payload accepted")
    } catch ProjectSourceFiles.Failure.noteEncodingTooLarge {}
    expect(try files() == filesBefore)
    print("ProjectSourceStorageChecks: passed (production note/store paths, actual file/SQLite reopen, edit and shared-file retention, 24 suspended-write races, failed SQL rollback/retry, local error presentation, workspace and size guards; model state/evidence notification are fixtures, no network)")
  }

  @MainActor private static func race(root: URL, edit: Bool, mode: Int, project: MemoraSpace) async throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("race-\(edit)-\(mode).sqlite"))
    model.spaces = [project]
    let id = try await model.addProjectNote(title: "元の名前", text: "元の本文", projectID: project.id)!
    let original = model.source(id: id)!
    let before = try files()
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let hold = Task.detached { await ProjectSourceFiles.shared.holdForSourceStorageCheck(entered: entered, release: release) }
    defer { release.signal() }
    precondition(entered.wait(timeout: .now() + 10) == .success)
    var started = false
    let operation = Task { @MainActor in
      started = true
      if edit { return try await model.updateProjectNote(id, title: "遅れた編集", text: "遅れた本文") }
      return try await model.addProjectNote(title: "遅れた追加", text: "遅れた本文", projectID: project.id) != nil
    }
    while !started { await Task.yield() }
    switch mode {
    case 0: model.currentTeamID = "other"
    case 1: model.currentTeamID = "other"; model.currentTeamID = nil
    case 2: model.isRestoring = true
    case 3: model.isStoreProtected = true
    case 4: model.spaces = []
    case 5: model.spaces[0].name = "別の保存先の状態"
    case 6: operation.cancel()
    case 7 where edit: model.projectSources[0].privacy.protect(.personal)
    case 8 where edit: model.projectSources[0].projectID = nil
    case 9 where edit: model.projectSources[0].title = "先行する別の編集"
    case 10 where edit: model.projectSources = []
    case 11 where edit: model.projectSources[0].kind = .web
    default: model.aiWorkspaceGeneration = UUID()
    }
    let snapshot = model.projectSources
    if edit && (7...11).contains(mode) {
      precondition(model.persistNow(snapshot, forKey: MemoraModel.StorageKey.projectSources))
    }
    let durableSnapshot = try reload(model)
    release.signal()
    let held = await hold.value
    let saved = try await operation.value
    precondition(held && !saved && model.projectSources == snapshot)
    expect(try files() == before)
    // The original bytes and any intervening durable edit survive the late write.
    expect(try text(original) == "元の本文" && reload(model) == durableSnapshot)
  }

  @MainActor private static func rollback(root: URL, edit: Bool, local: Bool, project: MemoraSpace) async throws {
    let url = root.appendingPathComponent("rollback-\(edit)-\(local).sqlite")
    let model = try MemoraModel(storeURL: url)
    model.spaces = [project]
    let id = try await model.addProjectNote(title: "保持する名前", text: "保持する本文", projectID: project.id)!
    let original = model.source(id: id)!
    let before = try files()
    try sql("CREATE TRIGGER fail_source BEFORE INSERT ON documents WHEN NEW.key = 'memoraProjectSources' BEGIN SELECT RAISE(ABORT, 'source check'); END;", url: url)
    let saved: Bool
    if edit { saved = try await model.updateProjectNote(id, title: "再保存する名前", text: "再保存する本文", presentsErrorsLocally: local) }
    else { saved = try await model.addProjectNote(title: "再保存する名前", text: "再保存する本文", projectID: project.id, presentsErrorsLocally: local) != nil }
    precondition(!saved && model.projectSources == [original])
    precondition((model.persistenceFailureMessage == nil) == local && model.failurePresentation.shouldPresentGlobally)
    expect(try reload(model) == [original] && files() == before && text(original) == "保持する本文")
    try sql("DROP TRIGGER fail_source;", url: url)
    if edit { expect(try await model.updateProjectNote(id, title: "再保存する名前", text: "再保存する本文", presentsErrorsLocally: local)) }
    else { expect(try await model.addProjectNote(title: "再保存する名前", text: "再保存する本文", projectID: project.id, presentsErrorsLocally: local) != nil) }
    expect(try reload(model) == model.projectSources)
  }

  private static func expect(_ condition: Bool) { precondition(condition) }

  @MainActor private static func draftReads(root: URL) throws {
    let url = root.appendingPathComponent("draft-reads.sqlite")
    let store = LocalStore(fileURL: url)
    try store.prepare()
    RecordStore.store = store
    let key = "editor"
    precondition(DraftStore.read(key) == .absent)
    try DraftStore.saveAndWait("", key: key)
    precondition(DraftStore.read(key) == .text(""))
    let original = "日本語の下書き\n\"引用\""
    try DraftStore.saveAndWait(original, key: key)
    precondition(DraftStore.read(key) == .text(original) && DraftStore.load(key) == original)
    RecordStore.failsReading = true
    precondition(DraftStore.read(key) == .unreadable)
    RecordStore.failsReading = false
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    RecordStore.store = reopened
    precondition(DraftStore.read(key) == .text(original))
    try store.write(DraftStore.storageKey(for: key), data: JSONEncoder().encode(original))
    precondition(DraftStore.read(key) == .text(original)) // Earlier JSON-string drafts.
    for data in [Data("not JSON".utf8), Data([1, 255]), Data()] {
      try store.write(DraftStore.storageKey(for: key), data: data)
      precondition(DraftStore.read(key) == .unreadable)
      guard case .data(let retained) = store.readOutcome(DraftStore.storageKey(for: key)), retained == data else {
        preconditionFailure("Reading an invalid draft changed its original bytes")
      }
    }
    print("Draft reads: absent/empty/legacy/reopen, read failure and malformed UTF-8 preserved")
  }

  @MainActor private static func linkDraftCommit(root: URL, project: MemoraSpace) throws {
    for duplicate in [false, true] {
      let url = root.appendingPathComponent("link-draft-\(duplicate).sqlite")
      let model = try MemoraModel(storeURL: url)
      model.spaces = [project]
      RecordStore.store = model.store
      if duplicate { _ = try model.addProjectLink("https://example.org/page?utm_source=old", projectID: project.id) }
      let previous = model.projectSources
      let preparations = model.linkPreparationIDs
      let bodyKey = "workspace.newMemo.\(project.id)"
      let titleKey = bodyKey + ".title"
      let keys = [bodyKey, titleKey].map { DraftStore.storageKey(for: $0) }
      let link = "https://EXAMPLE.org/page?utm_source=new#position"
      try DraftStore.saveAndWait(link, key: bodyKey)
      try DraftStore.saveAndWait("残すタイトル", key: titleKey)
      try sql("CREATE TRIGGER fail_link_draft BEFORE DELETE ON documents WHEN OLD.key = '\(keys[1])' BEGIN SELECT RAISE(ABORT, 'link draft'); END;", url: url)
      expect(try model.addProjectLink(link, projectID: project.id, removing: keys) == nil)
      precondition(model.projectSources == previous && model.linkPreparationIDs == preparations)
      precondition(DraftStore.read(bodyKey) == .text(link) && DraftStore.read(titleKey) == .text("残すタイトル"))
      if previous.isEmpty {
        guard case .missing = model.store.readOutcome(MemoraModel.StorageKey.projectSources) else {
          preconditionFailure("Failed link commit left a source document")
        }
      } else { expect(try reload(model) == previous) }
      try sql("DROP TRIGGER fail_link_draft;", url: url)
      let id = try model.addProjectLink(link, projectID: project.id, removing: keys)!
      precondition(model.projectSources.count == previous.count + (duplicate ? 0 : 1))
      precondition(model.linkPreparationIDs.count == preparations.count + (duplicate ? 0 : 1))
      if duplicate { precondition(model.projectSources == previous && previous[0].id == id) }
      precondition(DraftStore.read(bodyKey) == .absent && DraftStore.read(titleKey) == .absent)
      expect(try reload(model) == model.projectSources)
    }
    print("URL drafts: new/deduplicated source, atomic removal, rollback and no duplicate preparation passed")
  }

  @MainActor private static func failedLinkRetry(root: URL, project: MemoraSpace) throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("link-retry.sqlite"))
    model.spaces = [project]
    RecordStore.store = model.store
    let link = "https://example.org/retry-\(UUID().uuidString)"
    let id = try model.addProjectLink(link, projectID: project.id)!
    let afterAdd = model.linkPreparationIDs.count
    var failed = model.source(id: id)!
    failed.processingStatus = .failed
    failed.errorInformation = "取得できませんでした"
    expect(model.storeProjectSource(failed))
    let retried = try model.addProjectLink(link, projectID: project.id)!
    precondition(retried == id && model.projectSources.count == 1, "a retry must reuse the same record")
    precondition(model.linkPreparationIDs.count == afterAdd + 1, "re-adding a failed source must retry preparation")
    var ready = model.source(id: id)!
    ready.processingStatus = .ready
    ready.extractedTextReference = "retained-text.json"
    expect(model.storeProjectSource(ready))
    _ = try model.addProjectLink(link, projectID: project.id)
    precondition(model.linkPreparationIDs.count == afterAdd + 1, "a readable duplicate must not be re-fetched")
    print("URL retry: failed source re-added retries the same id; readable duplicate is not re-fetched")
  }

  @MainActor private static func noteDraftCommit(root: URL, project: MemoraSpace) async throws {
    let url = root.appendingPathComponent("memo-draft.sqlite")
    let model = try MemoraModel(storeURL: url)
    model.spaces = [project]
    let key = "draft.workspace.newMemo.\(project.id)"
    try model.store.write(key, data: Data("Draft to keep until the note is committed".utf8))
    try FileManager.default.createDirectory(at: ProjectSourceFiles.directory, withIntermediateDirectories: true)
    let before = try files()
    try sql("CREATE TRIGGER fail_draft BEFORE DELETE ON documents WHEN OLD.key = '\(key)' BEGIN SELECT RAISE(ABORT, 'draft removal'); END;", url: url)
    expect(try await model.addProjectNote(title: "メモ", text: "本文", projectID: project.id, removing: [key]) == nil)
    precondition(model.projectSources.isEmpty)
    expect(try files() == before)
    guard case .data = model.store.readOutcome(key) else { preconditionFailure("Failed commit lost the draft") }
    try sql("DROP TRIGGER fail_draft;", url: url)
    let id = try await model.addProjectNote(title: "メモ", text: "本文", projectID: project.id, removing: [key])!
    precondition(model.source(id: id)?.projectID == project.id)
    expect(try reload(model) == model.projectSources)
    guard case .missing = model.store.readOutcome(key) else { preconditionFailure("Committed memo left a duplicate draft") }
    print("Memo draft: atomic commit/removal and SQLite delete-failure rollback passed")
  }
  private static func text(_ source: ProjectSource) throws -> String {
    try ProjectSourceTextReader.read(source.extractedTextReference!).map(\.text).joined(separator: "\n")
  }
  @MainActor private static func reload(_ model: MemoraModel) throws -> [ProjectSource] {
    let store = LocalStore(fileURL: model.storeURL)
    try store.prepare()
    guard case .data(let bytes) = store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Source document is missing") }
    return try JSONDecoder().decode([ProjectSource].self, from: bytes)
  }
  private static func files() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
  }
  private static func sql(_ statement: String, url: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
  }
}

extension ProjectSourceFiles {
  func holdForSourceStorageCheck(entered: DispatchSemaphore, release: DispatchSemaphore) -> Bool {
    entered.signal()
    return release.wait(timeout: .now() + 10) == .success
  }
}
