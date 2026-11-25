import Foundation

struct Meeting {
  var id = UUID()
  var createdAt = Date.now
  var displayTitle = "写真の記録"
  var photoFileNames: [String]?
}

@MainActor
final class MemoraModel {
  var currentTeamID: String?
  var isRestoring = false
  var isStoreProtected = false
  var aiWorkspaceGeneration = UUID()
  var meetings: [Meeting] = []
  var mediaIndexEntries: [MediaIndexEntry] = []
  let storeURL: URL
  let store: LocalStore

  init(_ name: String) throws {
    storeURL = MediaFiles.fixtureRoot.appendingPathComponent("\(name).sqlite")
    store = LocalStore(fileURL: storeURL)
    try store.prepare()
  }

  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func persistNow(_ entries: [MediaIndexEntry], forKey key: String) -> Bool {
    do {
      try store.write(key, data: JSONEncoder().encode(entries))
      return true
    } catch { return false }
  }

  func persistedEntries() throws -> [MediaIndexEntry] {
    let reopened = LocalStore(fileURL: storeURL)
    try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome(MediaIndexEntry.storageKey) else {
      preconditionFailure("Missing media index on reopening SQLite")
    }
    return try JSONDecoder().decode([MediaIndexEntry].self, from: data)
  }
}

enum MediaFiles {
  static let fixtureRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

  static func photoURL(_ name: String) -> URL? {
    fixtureRoot.appendingPathComponent(name)
  }

  static func pixelSize(ofPhotoNamed name: String) -> (width: Int, height: Int)? { (1, 1) }
}

/// Vision completion is controlled so an index mutation can occur during recognition.
@MainActor
enum MediaTextRecognizer {
  static var read: (String) async -> String? = { _ in nil }

  static func read(photoNamed name: String) async -> String? { await read(name) }
}
