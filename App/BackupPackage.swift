import Foundation

/// A versioned export of the app's records and media, written as a folder
/// package so it needs no archive format. API keys are never included.
enum BackupPackage {
  static let manifestName = "manifest.json"
  static let mediaFolderName = "media"
  static let currentVersion = 1

  struct Manifest: Codable {
    var version: Int
    var exportedAt: Date
    var meetings: [Meeting]
    var spaces: [MemoraSpace]
    var tasks: [MemoraTask]
    var lifeLogEntries: [LifeLogEntry]
    var people: [Person]
    var aiHistory: [AIConversationEntry]
    /// Audio file names, stored under the media folder on restore.
    var audioFileNames: [String]
    /// Photo file names, stored under the media folder on restore.
    var photoFileNames: [String]
  }

  enum BackupError: LocalizedError {
    case notEmpty
    case unreadable
    case unsupportedVersion(Int)
    case duplicateIdentifiers
    case missingMedia([String])
    case unsafeName(String)

    var errorDescription: String? {
      switch self {
      case .notEmpty:
        "この端末にすでに記録があります。復元は、記録が空のときだけ行えます。"
      case .unreadable:
        "バックアップを読み込めませんでした。フォルダとファイルを確認してください。"
      case .unsupportedVersion(let version):
        "このバックアップは対応していない版です（版\(version)）。"
      case .duplicateIdentifiers:
        "バックアップに同じIDの項目が含まれています。"
      case .missingMedia(let names):
        "バックアップに媒体ファイルが足りません: \(names.prefix(3).joined(separator: ", "))"
      case .unsafeName(let name):
        "バックアップに安全でないファイル名が含まれています: \(name)"
      }
    }
  }

  /// Writes a package into `directory` (created if needed) and returns its URL.
  static func write(
    meetings: [Meeting],
    spaces: [MemoraSpace],
    tasks: [MemoraTask],
    lifeLogEntries: [LifeLogEntry],
    people: [Person],
    aiHistory: [AIConversationEntry],
    into directory: URL
  ) throws -> URL {
    let fileManager = FileManager.default
    let packageURL = directory.appendingPathComponent(packageName(), isDirectory: true)
    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)
    try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)

    // Collect the media that the records point at.
    var audioNames: [String] = []
    var photoNames: [String] = []

    for meeting in meetings {
      if let audioURL = meeting.audioURL,
         let name = MediaFiles.reference(for: audioURL),
         copy(audioURL, named: name, into: mediaURL) {
        audioNames.append(name)
      }
      for name in MediaFiles.photoFiles(for: meeting.photoFileNames ?? []) {
        if let url = MediaFiles.photoURL(name), copy(url, named: name, into: mediaURL) {
          photoNames.append(name)
        }
      }
    }

    let manifest = Manifest(
      version: currentVersion,
      exportedAt: .now,
      meetings: meetings,
      spaces: spaces,
      tasks: tasks,
      lifeLogEntries: lifeLogEntries,
      people: people,
      aiHistory: aiHistory,
      audioFileNames: audioNames,
      photoFileNames: photoNames
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(manifest)
    try data.write(to: packageURL.appendingPathComponent(manifestName), options: .atomic)

    return packageURL
  }

  /// Reads and validates a package. Media is copied into the app's folders by
  /// `install(mediaFrom:)` once the records are accepted.
  static func read(from packageURL: URL) throws -> Manifest {
    let data: Data
    do {
      data = try Data(contentsOf: packageURL.appendingPathComponent(manifestName))
    } catch {
      throw BackupError.unreadable
    }

    guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
      throw BackupError.unreadable
    }
    guard manifest.version == currentVersion else {
      throw BackupError.unsupportedVersion(manifest.version)
    }

    try validateIdentifiers(manifest)

    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)
    var missing: [String] = []
    for name in manifest.audioFileNames + manifest.photoFileNames {
      if !isSafe(name) { throw BackupError.unsafeName(name) }
      if !FileManager.default.fileExists(atPath: mediaURL.appendingPathComponent(name).path) {
        missing.append(name)
      }
    }
    guard missing.isEmpty else { throw BackupError.missingMedia(missing) }

    return manifest
  }

  /// Copies a package's media back into the app's folders.
  static func install(mediaFrom packageURL: URL, manifest: Manifest) throws {
    let fileManager = FileManager.default
    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)

    try fileManager.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: MediaFiles.photosDirectory, withIntermediateDirectories: true)

    for name in manifest.audioFileNames {
      copy(from: mediaURL.appendingPathComponent(name), to: MediaFiles.directory.appendingPathComponent(name))
    }
    for name in manifest.photoFileNames {
      copy(from: mediaURL.appendingPathComponent(name), to: MediaFiles.photosDirectory.appendingPathComponent(name))
    }
  }

  private static func packageName() -> String {
    let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    return "Memora-\(stamp)"
  }

  @discardableResult
  private static func copy(_ url: URL, named name: String, into directory: URL) -> Bool {
    copy(from: url, to: directory.appendingPathComponent(name))
  }

  @discardableResult
  private static func copy(from source: URL, to destination: URL) -> Bool {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path) else { return false }
    if fileManager.fileExists(atPath: destination.path) { return true }
    return (try? fileManager.copyItem(at: source, to: destination)) != nil
  }

  /// A stored media name must be a plain file name, so a package can never write
  /// outside the folders it is handed.
  private static func isSafe(_ name: String) -> Bool {
    !name.isEmpty && !name.contains("/") && !name.contains("..")
  }

  private static func validateIdentifiers(_ manifest: Manifest) throws {
    func hasDuplicates<T: Hashable>(_ values: [T]) -> Bool {
      var seen = Set<T>()
      return values.contains { !seen.insert($0).inserted }
    }

    guard !hasDuplicates(manifest.meetings.map(\.id)),
          !hasDuplicates(manifest.spaces.map(\.id)),
          !hasDuplicates(manifest.tasks.map(\.id)),
          !hasDuplicates(manifest.lifeLogEntries.map(\.id)),
          !hasDuplicates(manifest.people.map(\.id)),
          !hasDuplicates(manifest.aiHistory.map(\.id)) else {
      throw BackupError.duplicateIdentifiers
    }
  }
}
