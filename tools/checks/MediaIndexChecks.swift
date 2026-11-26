import Foundation
import SQLite3

@main
struct MediaIndexChecks {
  @MainActor static func main() async throws {
    try await mergesIntoCurrentIndex()
    try await prioritizesRequestedPhotos()
    try await preparesLibrarySearchInBoundedVisits()
    try await buildsRecordPhotoEvidence()
    try await rejectsStaleRecognition()
    try await reindexesChangedOriginal()
    try await rollsBackWriteFailure()
    print("MediaIndexChecks: passed (scoped recognition, live file revision, SQLite reopen, legacy invalidation, merge, deletion, cancellation, restore and write failure; Vision callback/model state are fixtures)")
  }

  @MainActor static func buildsRecordPhotoEvidence() async throws {
    let model = try MemoraModel("record-photo-evidence")
    let original = try photo("record-photo-original")
    let other = try photo("record-photo-other")
    let record = Meeting(photoFileNames: [original])
    model.meetings = [record, Meeting(photoFileNames: [other])]
    MediaTextRecognizer.read = { name in name == original ? "水晶の決定事項" : "他の記録の機密事項" }
    let context = await model.recordPhotoContext(record, question: "水晶の決定事項", budget: 500)
    precondition(context.text.hasPrefix("【写真1】") && context.text.contains("水晶の決定事項"))
    precondition(!context.text.contains("他の記録の機密事項") && context.used.count == 1)
    let citation = context.used[0]
    precondition(citation.target == .meeting(record.id) && citation.photo?.name == original)
    precondition(model.currentPhotoEvidence(citation)?.name == original)
    let persisted = try model.persistedEntries()
    precondition(persisted.first { $0.name == other }?.textReadAt == nil)
    var alteredCitation = citation
    alteredCitation.excerpt = "元画像にない情報"
    precondition(model.currentPhotoEvidence(alteredCitation) == nil)
    model.isStoreProtected = true
    precondition(model.currentPhotoEvidence(citation) == nil)
    let locked = await model.recordPhotoContext(record, question: "水晶の決定事項", budget: 500)
    precondition(locked.used.isEmpty)
    model.isStoreProtected = false
    try replace(original, version: 2)
    precondition(model.currentPhotoEvidence(citation) == nil)
  }

  @MainActor static func prioritizesRequestedPhotos() async throws {
    let model = try MemoraModel("scope")
    let requested = try photo("requested")
    let other = try photo("unrelated")
    model.meetings = [Meeting(createdAt: .distantPast, photoFileNames: [requested]), Meeting(photoFileNames: [other])]
    precondition(model.reconcileMediaIndex() && model.mediaIndexEntries.first?.name == other)
    MediaTextRecognizer.read = { name in name }
    let count = await model.readPendingMediaText(for: [requested], limit: 1)
    let persisted = try model.persistedEntries()
    precondition(count == 1 && persisted.first { $0.name == requested }?.text == requested)
    precondition(persisted.first { $0.name == other }?.textReadAt == nil)
  }

  @MainActor static func preparesLibrarySearchInBoundedVisits() async throws {
    let model = try MemoraModel("library-search")
    let records = try (0..<13).map { index in
      try Meeting(photoFileNames: [photo("library-\(index)")])
    }
    model.meetings = records
    MediaTextRecognizer.read = { _ in "図面の確認項目" }
    model.currentTeamID = "another-workspace"
    await model.preparePhotoSearchIndex()
    precondition(model.mediaIndexEntries.isEmpty)
    model.currentTeamID = nil
    await model.preparePhotoSearchIndex()
    let first = model.photoRecordIDs(matching: "図面")
    precondition(first.count == 12)
    await model.preparePhotoSearchIndex()
    let second = model.photoRecordIDs(matching: "図面")
    precondition(second == Set(records.map(\.id)) && first.isSubset(of: second))
  }

  @MainActor static func mergesIntoCurrentIndex() async throws {
    let model = try MemoraModel("merge")
    let first = try photo("merge-first")
    let second = try photo("merge-second")
    model.meetings = [Meeting(photoFileNames: [first])]
    precondition(model.reconcileMediaIndex())
    let (gate, job) = await startPendingRead(model)
    model.meetings[0].displayTitle = "変更後のタイトル"
    model.meetings.append(Meeting(photoFileNames: [second]))
    precondition(model.reconcileMediaIndex())
    gate.complete("写真にある決定事項")
    let count = await job.value
    precondition(count == 1)
    let persisted = try model.persistedEntries()
    precondition(persisted.count == 2)
    precondition(persisted.first { $0.name == first }?.recordTitle == "変更後のタイトル")
    precondition(persisted.first { $0.name == first }?.text == "写真にある決定事項")
    precondition(persisted.first { $0.name == second }?.textReadAt == nil)
  }

  @MainActor static func rejectsStaleRecognition() async throws {
    for mutation in ["deletion", "file", "restore", "switch", "lock", "cancel"] {
      let model = try MemoraModel(mutation)
      let name = try photo(mutation)
      model.meetings = [Meeting(photoFileNames: [name])]
      precondition(model.reconcileMediaIndex())
      let (gate, job) = await startPendingRead(model)
      switch mutation {
      case "deletion":
        model.meetings.removeAll()
        precondition(model.reconcileMediaIndex())
      case "file":
        try replace(name, version: 2)
      case "restore":
        model.aiWorkspaceGeneration = UUID()
        model.isRestoring = true
      case "switch":
        model.currentTeamID = "別のワークスペース"
        model.aiWorkspaceGeneration = UUID()
        model.currentTeamID = nil
        model.aiWorkspaceGeneration = UUID()
      case "lock":
        model.isStoreProtected = true
      case "cancel":
        job.cancel()
      default: preconditionFailure("Unknown fixture mutation")
      }
      gate.complete("失効した写真OCR")
      let count = await job.value
      precondition(count == 0)
      let persisted = try model.persistedEntries()
      precondition(!persisted.contains { $0.textReadAt != nil || !$0.text.isEmpty })
      if mutation == "deletion" { precondition(persisted.isEmpty && model.mediaIndexEntries.isEmpty) }
    }
  }

  @MainActor static func reindexesChangedOriginal() async throws {
    let model = try MemoraModel("revision")
    let name = try photo("revision")
    let meeting = Meeting(photoFileNames: [name])
    model.meetings = [meeting]
    // Optional fileModifiedAt is omitted in the legacy stored form.
    let legacy = MediaIndexEntry(name: name, recordID: meeting.id, recordTitle: meeting.displayTitle,
      recordDate: meeting.createdAt, byteCount: 1, pixelWidth: 1, pixelHeight: 1, text: "旧OCR", textReadAt: .now)
    precondition(model.persistNow([legacy], forKey: MediaIndexEntry.storageKey))
    model.mediaIndexEntries = try model.persistedEntries()
    precondition(!model.mediaIndexEntryHasLiveOriginal(legacy) && model.reconcileMediaIndex())
    precondition(model.mediaIndexEntries.first?.textReadAt == nil)

    MediaTextRecognizer.read = { _ in "現在の原本" }
    let count = await model.readPendingMediaText()
    precondition(count == 1 && model.mediaIndexEntries.first?.text == "現在の原本")
    let oldEntry = model.mediaIndexEntries[0]
    precondition(model.photoRecordIDs(matching: "現在 原本") == [meeting.id])
    precondition(model.photoRecordIDs(matching: "現在 未入力").isEmpty)
    model.isStoreProtected = true
    precondition(model.photoRecordIDs(matching: "原本").isEmpty)
    model.isStoreProtected = false
    model.currentTeamID = "another-workspace"
    precondition(model.photoRecordIDs(matching: "原本").isEmpty)
    model.currentTeamID = nil
    try replace(name, version: 2)
    precondition(model.photoRecordIDs(matching: "原本").isEmpty)
    precondition(!model.mediaIndexEntryHasLiveOriginal(oldEntry) && model.reconcileMediaIndex())
    precondition(model.mediaIndexEntries.first?.byteCount == oldEntry.byteCount)
    precondition(model.mediaIndexEntries.first?.text == "" && model.mediaIndexEntries.first?.textReadAt == nil)

    try FileManager.default.removeItem(at: MediaFiles.photoURL(name)!)
    precondition(model.reconcileMediaIndex() && model.mediaIndexEntries.isEmpty)
    let persisted = try model.persistedEntries()
    precondition(persisted.isEmpty)
  }

  @MainActor static func rollsBackWriteFailure() async throws {
    let model = try MemoraModel("write-failure")
    let name = try photo("write-failure")
    model.meetings = [Meeting(photoFileNames: [name])]
    precondition(model.reconcileMediaIndex())
    var database: OpaquePointer?
    precondition(sqlite3_open(model.storeURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let trigger = "CREATE TRIGGER reject_index BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;"
    precondition(sqlite3_exec(database, trigger, nil, nil, nil) == SQLITE_OK)
    MediaTextRecognizer.read = { _ in "再試行できる結果" }
    let failed = await model.readPendingMediaText()
    precondition(failed == 0 && model.mediaIndexEntries.first?.textReadAt == nil)
    let persisted = try model.persistedEntries()
    precondition(persisted.first?.textReadAt == nil)
    precondition(sqlite3_exec(database, "DROP TRIGGER reject_index;", nil, nil, nil) == SQLITE_OK)
    let retried = await model.readPendingMediaText()
    precondition(retried == 1 && model.mediaIndexEntries.first?.text == "再試行できる結果")
  }

  @MainActor private static func startPendingRead(_ model: MemoraModel) async -> (RecognitionGate, Task<Int, Never>) {
    let gate = RecognitionGate()
    MediaTextRecognizer.read = { _ in await gate.recognize() }
    let job = Task { await model.readPendingMediaText(limit: 1) }
    await gate.entered()
    return (gate, job)
  }

  static func photo(_ prefix: String) throws -> String {
    let name = "\(prefix).jpg"
    try replace(name, version: 1)
    return name
  }

  static func replace(_ name: String, version: UInt8) throws {
    let url = MediaFiles.photoURL(name)!
    try Data([version]).write(to: url, options: .atomic)
    let date = Date(timeIntervalSince1970: 1_750_000_000 + Double(version))
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
  }
}

@MainActor
private final class RecognitionGate {
  private var recognition: CheckedContinuation<String?, Never>?
  private var waiting: CheckedContinuation<Void, Never>?

  func recognize() async -> String? {
    await withCheckedContinuation { continuation in
      recognition = continuation
      waiting?.resume()
      waiting = nil
    }
  }

  func entered() async {
    guard recognition == nil else { return }
    await withCheckedContinuation { waiting = $0 }
  }

  func complete(_ text: String?) {
    recognition?.resume(returning: text)
    recognition = nil
  }
}
