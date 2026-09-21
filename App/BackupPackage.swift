import Foundation

/// A versioned export of the app's records and media, written as a folder
/// package so it needs no archive format. API keys are never included.
///
/// An export either carries everything the records point at or reports what it
/// could not, and it never writes into a folder a previous export used. A
/// restore is verified in a staging area first and only then moved into place.
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
    /// A record points at a file name that is not a plain file name.
    case unsafeReference(String)
    /// A record points at a file that is not on this device any more.
    case missingSource([String])
    /// A file that is on this device could not be copied into the package.
    case copyFailed([String])
    /// The package does not hold a file one of its records needs.
    case missingMedia([String])
    /// The media could not be put in place, so nothing was restored.
    case mediaInstallFailed([String])

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
      case .unsafeReference(let name):
        "記録に安全でないファイル名が含まれています: \(name)"
      case .missingSource(let names):
        "この端末に見つからないファイルがあるため、完全なバックアップを作成できません: \(names.prefix(3).joined(separator: ", "))"
      case .copyFailed(let names):
        "バックアップにコピーできないファイルがあります: \(names.prefix(3).joined(separator: ", "))"
      case .missingMedia(let names):
        "バックアップに不足しているファイルがあります: \(names.prefix(3).joined(separator: ", "))"
      case .mediaInstallFailed(let names):
        "バックアップの媒体を配置できませんでした。復元は行っていません: \(names.prefix(3).joined(separator: ", "))"
      }
    }
  }

  /// Writes a package into `directory` and returns its URL. Every file the
  /// records point at must be present and copyable, or the export reports which
  /// ones stopped it instead of writing an incomplete backup.
  static func write(
    meetings: [Meeting],
    spaces: [MemoraSpace],
    tasks: [MemoraTask],
    lifeLogEntries: [LifeLogEntry],
    people: [Person],
    aiHistory: [AIConversationEntry],
    into directory: URL
  ) throws -> URL {
    let plan = try collectMedia(meetings: meetings, lifeLogEntries: lifeLogEntries)

    // A folder of its own for every export, so nothing from an earlier one can
    // be carried over.
    let packageURL = directory.appendingPathComponent(packageName(), isDirectory: true)
    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
    } catch {
      throw BackupError.copyFailed([packageURL.lastPathComponent])
    }

    var audioNames: [String] = []
    var photoNames: [String] = []
    var failed: [String] = []

    for file in plan.required {
      let destination = mediaURL.appendingPathComponent(file.name)
      if copy(from: file.url, to: destination) {
        if file.isAudio {
          audioNames.append(file.name)
        } else {
          photoNames.append(file.name)
        }
      } else {
        failed.append(file.name)
      }
    }
    guard failed.isEmpty else {
      try? FileManager.default.removeItem(at: packageURL)
      throw BackupError.copyFailed(failed)
    }

    // Thumbnails are small copies that can always be built again from the
    // original, so a missing one is not a reason to fail the export.
    for file in plan.regenerable {
      _ = copy(
        from: file.url,
        to: mediaURL.appendingPathComponent(file.name)
      )
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
    do {
      let data = try encoder.encode(manifest)
      try data.write(to: packageURL.appendingPathComponent(manifestName), options: .atomic)
    } catch {
      try? FileManager.default.removeItem(at: packageURL)
      throw BackupError.copyFailed([manifestName])
    }

    return packageURL
  }

  /// Reads and validates a package: identifiers, file names, and every file each
  /// record points at. Media is only put in place by `install(mediaFrom:)`.
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

    // The package's own list is checked, and so is every reference a record
    // holds, so a record can never be restored pointing at a file that is not
    // in the package.
    let listed = Set(manifest.audioFileNames + manifest.photoFileNames)
    for name in listed where !MediaFiles.isPlainName(name) {
      throw BackupError.unsafeReference(name)
    }

    let referenced = try referencedMedia(manifest)
    var missing: [String] = []
    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)
    for name in referenced.requiredAudio.union(referenced.requiredPhotos) {
      guard listed.contains(name),
            FileManager.default.fileExists(atPath: mediaURL.appendingPathComponent(name).path) else {
        missing.append(name)
        continue
      }
    }
    // A file the package lists must really be there.
    for name in listed where !FileManager.default.fileExists(atPath: mediaURL.appendingPathComponent(name).path) {
      missing.append(name)
    }
    guard missing.isEmpty else { throw BackupError.missingMedia(Array(Set(missing)).sorted()) }

    return manifest
  }

  /// Verifies the package's media into a staging area, then moves it into the
  /// app's folders. Nothing lands in the app until every file is present, and a
  /// failure part-way takes back whatever was already moved.
  static func install(mediaFrom packageURL: URL, manifest: Manifest) throws {
    let fileManager = FileManager.default
    let staging = fileManager.temporaryDirectory
      .appendingPathComponent("MemoraRestore-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }

    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    } catch {
      throw BackupError.mediaInstallFailed([staging.lastPathComponent])
    }

    let mediaURL = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)

    // 1. Stage every file, checking that it really arrives.
    var staged: [(name: String, url: URL, isAudio: Bool)] = []
    for (names, isAudio) in [(manifest.audioFileNames, true), (manifest.photoFileNames, false)] {
      for name in names {
        guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
        let source = mediaURL.appendingPathComponent(name)
        let destination = staging.appendingPathComponent(name)
        guard copy(from: source, to: destination) else {
          throw BackupError.mediaInstallFailed([name])
        }
        staged.append((name, destination, isAudio))
      }
    }

    // 2. Move them into place, taking back what moved if one fails.
    do {
      try fileManager.createDirectory(at: MediaFiles.directory, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: MediaFiles.photosDirectory, withIntermediateDirectories: true)
    } catch {
      throw BackupError.mediaInstallFailed([MediaFiles.directory.lastPathComponent])
    }

    var installed: [URL] = []
    for file in staged {
      let folder = file.isAudio ? MediaFiles.directory : MediaFiles.photosDirectory
      guard MediaFiles.isInside(staging.appendingPathComponent(file.name), folder: staging) else {
        throw BackupError.unsafeReference(file.name)
      }
      let destination = folder.appendingPathComponent(file.name)
      do {
        if fileManager.fileExists(atPath: destination.path) {
          try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: file.url, to: destination)
        installed.append(destination)
      } catch {
        for url in installed {
          try? fileManager.removeItem(at: url)
        }
        throw BackupError.mediaInstallFailed([file.name])
      }
    }
  }

  /// Removes media an aborted restore had already put in place, so a failure
  /// while writing the records leaves the device as it was.
  static func removeInstalledMedia(_ names: [String], isAudio: Bool) {
    let folder = isAudio ? MediaFiles.directory : MediaFiles.photosDirectory
    for name in names where MediaFiles.isPlainName(name) {
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
  }

  private static func packageName() -> String {
    let stamp = Date().formatted(
      .iso8601.year().month().day().dateSeparator(.dash)
    )
    let time = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
    let suffix = UUID().uuidString.prefix(6)
    return "Memora-\(stamp)-\(time.replacingOccurrences(of: ":", with: ""))-\(suffix)"
  }

  private struct MediaFile {
    var name: String
    var url: URL
    var isAudio: Bool
  }

  private struct MediaPlan {
    var required: [MediaFile] = []
    var regenerable: [MediaFile] = []
  }

  /// Every file the records point at, split into what must be there and what can
  /// be built again.
  private static func collectMedia(meetings: [Meeting], lifeLogEntries: [LifeLogEntry]) throws -> MediaPlan {
    var plan = MediaPlan()
    var missing: [String] = []

    func addAudio(_ url: URL?) throws {
      guard let url else { return }
      guard let name = MediaFiles.reference(for: url) else {
        throw BackupError.unsafeReference(url.lastPathComponent)
      }
      guard FileManager.default.fileExists(atPath: url.path) else {
        missing.append(name)
        return
      }
      plan.required.append(MediaFile(name: name, url: url, isAudio: true))
    }

    func addPhoto(_ name: String) throws {
      guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
      for required in MediaFiles.requiredPhotoFiles(for: name) {
        guard let url = MediaFiles.photoURL(required),
              FileManager.default.fileExists(atPath: url.path) else {
          missing.append(required)
          continue
        }
        plan.required.append(MediaFile(name: required, url: url, isAudio: false))
      }
      for regenerable in MediaFiles.regenerablePhotoFiles(for: name) {
        guard let url = MediaFiles.photoURL(regenerable),
              FileManager.default.fileExists(atPath: url.path) else { continue }
        plan.regenerable.append(MediaFile(name: regenerable, url: url, isAudio: false))
      }
    }

    for meeting in meetings {
      try addAudio(meeting.audioURL)
      for name in meeting.photoFileNames ?? [] {
        try addPhoto(name)
      }
    }
    // Journal photos belong in a backup too.
    for entry in lifeLogEntries {
      if let name = entry.photoFileName {
        try addPhoto(name)
      }
    }

    guard missing.isEmpty else { throw BackupError.missingSource(Array(Set(missing)).sorted()) }
    return plan
  }

  /// The media names the records themselves reference, used to check a package
  /// before anything is installed.
  private static func referencedMedia(
    _ manifest: Manifest
  ) throws -> (requiredAudio: Set<String>, requiredPhotos: Set<String>) {
    var audio: Set<String> = []
    var photos: Set<String> = []

    for meeting in manifest.meetings {
      if let url = meeting.audioURL {
        if let name = MediaFiles.reference(for: url) {
          audio.insert(name)
        }
      }
      for name in meeting.photoFileNames ?? [] {
        guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
        photos.insert(name)
      }
    }
    for entry in manifest.lifeLogEntries {
      guard let name = entry.photoFileName else { continue }
      guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
      photos.insert(name)
    }

    return (audio, photos)
  }

  @discardableResult
  private static func copy(from source: URL, to destination: URL) -> Bool {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: source.path) else { return false }
    if fileManager.fileExists(atPath: destination.path) { return true }
    return (try? fileManager.copyItem(at: source, to: destination)) != nil
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
