import Foundation

enum MemoraWidgetSnapshotStore {
  static var fileURL: URL? {
    guard let configuredGroup = Bundle.main.object(forInfoDictionaryKey: "MemoraWidgetAppGroup") as? String else { return nil }
    #if DEBUG
    let group = configuredGroup + ".debug"
    #else
    let group = configuredGroup
    #endif
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
      .appendingPathComponent("MemoraWidgetSnapshot.v1.json")
  }

  static func read(from url: URL? = fileURL, now: Date = .now) -> MemoraWidgetSnapshot? {
    guard let url else { return nil }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 64 * 1024 + 1), data.count <= 64 * 1024,
          let snapshot = try? JSONDecoder().decode(MemoraWidgetSnapshot.self, from: data), snapshot.isValid(at: now) else { return nil }
    return snapshot
  }

  static func write(_ snapshot: MemoraWidgetSnapshot, to url: URL? = fileURL) throws {
    guard let url, snapshot.isValid(at: .now) else { throw StoreFailure.unavailable }
    let data = try JSONEncoder().encode(snapshot)
    guard data.count <= 64 * 1024 else { throw StoreFailure.unavailable }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    #if os(iOS)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    #else
    try data.write(to: url, options: [.atomic])
    #endif
  }

  static func clear() throws {
    guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  enum StoreFailure: Error { case unavailable }
}
