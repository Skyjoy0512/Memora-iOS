import Foundation
import SQLite3

@main enum SamplePreviewChecks {
  @MainActor static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memora-sample-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("fixture.sqlite")
    let model = try MemoraModel(url: url)
    var personal = SummarizedAudioSample.make()
    personal.id = UUID(); personal.title = "本人の記録"; personal.summary = "変更してはいけない本文"
    model.meetings = [personal]
    precondition(model.persistBatch { [(key: MemoraModel.StorageKey.meetings, data: try RecordStore.encoded(model.meetings))] })
    let otherKeys = ["spaces", "tasks", "people", "journal", "aiHistory", "documents"]
    for key in otherKeys { try model.store.write(key, data: Data(("既存の" + key).utf8)) }
    precondition(model.openSummarizedAudioSample())
    precondition(model.meetings.count == 2 && model.meetings[1] == personal)
    precondition(model.selectedTab == .library && model.librarySection == .files && model.libraryPath == [.meeting(SummarizedAudioSample.id)])
    precondition(model.meetings[0].audioURL == nil && model.meetings[0].rawAudioReference == nil)
    let reopened = LocalStore(fileURL: url); try reopened.prepare()
    guard case .data(let bytes) = reopened.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("sample not saved") }
    let records = try JSONDecoder().decode([Meeting].self, from: bytes)
    precondition(records == model.meetings)
    for key in otherKeys {
      guard case .data(let value) = reopened.readOutcome(key) else { preconditionFailure("collection lost") }
      precondition(value == Data(("既存の" + key).utf8))
    }
    model.meetings[0].summary = "本人が編集したサンプル"
    let existing = model.meetings
    precondition(model.openSummarizedAudioSample() && model.meetings == existing)
    for mode in 0..<3 {
      model.isRestoring = mode == 0; model.currentTeamID = mode == 1 ? "team" : nil; model.protected = mode == 2
      model.selectedTab = .home; model.libraryPath = [.meeting(personal.id)]
      precondition(!model.openSummarizedAudioSample() && model.meetings == existing)
      precondition(model.selectedTab == .home && model.libraryPath == [.meeting(personal.id)])
    }
    let failing = try MemoraModel(url: root.appendingPathComponent("rejected.sqlite"))
    failing.meetings = [personal]
    precondition(failing.persistBatch { [(key: MemoraModel.StorageKey.meetings, data: try RecordStore.encoded([personal]))] })
    var db: OpaquePointer?
    precondition(sqlite3_open(failing.storeURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_sample BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    precondition(!failing.openSummarizedAudioSample() && failing.meetings == [personal] && failing.selectedTab == .home)
    guard case .data(let unchanged) = failing.store.readOutcome(MemoraModel.StorageKey.meetings) else { preconditionFailure("original lost") }
    let retained = try JSONDecoder().decode([Meeting].self, from: unchanged)
    precondition(retained == [personal])
    print("SamplePreviewChecks: passed (production preview action/sample/Meeting codec + real SQLite, existing records/collections unchanged, duplicate and edited sample retained, restore/team/protection/failure refused before routing; container and routes are fixtures, no recording/AI)")
  }
}

@MainActor final class MemoraModel {
  var store: LocalStore
  var storeURL: URL
  var meetings: [Meeting] = []
  var isRestoring = false
  var currentTeamID: String?
  var protected = false
  var selectedTab = Destination.home
  var librarySection = Section.projects
  var libraryPath: [Route] = []
  enum Destination { case home, library }
  enum Section { case files, projects }
  enum Route: Equatable { case meeting(UUID) }
  enum StorageKey { static let meetings = "memoraMeetings" }
  init(url: URL) throws { storeURL = url; store = LocalStore(fileURL: url); try store.prepare() }
  func isStoreWritable() -> Bool { !protected }
  func persistBatch(meetings: [Meeting]? = nil, prepared: [UUID: Data] = [:],
                    _ build: () throws -> [(key: String, data: Data)]) -> Bool {
    do {
      var writes = try build()
      if let meetings { writes.append((key: "memoraMeetings", data: try RecordStore.encoded(meetings))) }
      try store.applyBatch(writes: writes, removing: [])
      return true
    } catch { return false }
  }
}

enum RecordStore {
  static func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}

// A display example must not read, generate or alter audio/photo files.
enum MediaFiles {
  static func resolve(_ value: String) -> URL? { preconditionFailure("Unexpected media access") }
  static func reference(for url: URL) -> String? { preconditionFailure("Unexpected media access") }
  static func writePhoto(_ data: Data) -> String? { preconditionFailure("Unexpected media access") }
  static func deletePhoto(_ name: String) { preconditionFailure("Unexpected media access") }
}
