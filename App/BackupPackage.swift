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
  static let currentVersion = 3

  struct Manifest: Codable {
    var version: Int
    var exportedAt: Date
    var meetings: [Meeting]
    var spaces: [MemoraSpace]
    var tasks: [MemoraTask]
    var lifeLogEntries: [LifeLogEntry]
    var people: [Person]
    var aiHistory: [AIConversationEntry]
    var aiMemories: [AIMemory]? = nil
    var mailDrafts: [MailDraft]? = nil
    var companyTemplates: [CompanyTemplate]? = nil
    var additionalWorkspaceFiles: [String] { (companyTemplates ?? []).map(\.fileReference) + (documents ?? []).flatMap(\.artifactFileReferences) }
    /// Documents and slides. Optional, so a package from before they existed
    /// still restores.
    var documents: [MemoraDocument]?
    var projectSources: [ProjectSource]? = nil
    var projectChats: [ProjectChatThread]? = nil
    var webResearchReports: [WebResearchReport]? = nil
    var customSkills: [MemoraSkill]? = nil
    var skillSelections: [SkillSelection]? = nil
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
    /// A file in the package would replace one that is already on the device.
    case mediaConflict(String)
    /// The package lists the same file as both audio and photo.
    case conflictingMedia(String)
    /// The package carries a record that still holds its photos inline.
    case inlineMediaUnsupported
    /// The store could not be read, so nothing may be written over it.
    case storeProtected
    case storeWriteFailed
    case personalWorkspaceRequired
    /// A recording or an unfinished draft is still in the way.
    case busy

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
      case .mediaConflict(let name):
        "この端末に同じ名前のファイルがあるため復元できません: \(name)"
      case .conflictingMedia(let name):
        "同じファイルが音声と写真の両方に含まれています: \(name)"
      case .inlineMediaUnsupported:
        "このバックアップは古い形式の写真を含むため、復元できません。"
      case .storeProtected:
        "保存データを読み込めなかったため、復元できません。アプリを再起動してください。"
      case .storeWriteFailed:
        "記録を保存できなかったため、復元を取り消しました。空き容量を確認して再試行してください。"
      case .personalWorkspaceRequired:
        "端末内のバックアップは、個人ワークスペースに切り替えてから行ってください。"
      case .busy:
        "録音・解析・声の登録・復元中、または未保存の下書きがあるため復元できません。処理を終了してから再試行してください。"
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
    aiMemories: [AIMemory] = [],
    mailDrafts: [MailDraft] = [],
    companyTemplates: [CompanyTemplate] = [],
    documents: [MemoraDocument] = [],
    projectSources: [ProjectSource] = [],
    projectChats: [ProjectChatThread] = [],
    webResearchReports: [WebResearchReport] = [],
    customSkills: [MemoraSkill] = [],
    skillSelections: [SkillSelection] = [],
    into directory: URL
  ) throws -> URL {
    guard documents.allSatisfy(\.hasValidRevisions) else { throw BackupError.unreadable }
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

    do {
      try ProjectWorkspaceBackup.export(projectSources, into: packageURL, additionalNames: companyTemplates.map(\.fileReference) + documents.flatMap(\.artifactFileReferences))
    } catch {
      try? FileManager.default.removeItem(at: packageURL)
      throw error
    }

    let manifest = Manifest(
      // Older apps must refuse a package whose extra originals they would drop.
      version: meetings.contains(where: { !$0.originalAudioFileNames.isEmpty }) ? currentVersion : 2,
      exportedAt: .now,
      meetings: meetings,
      spaces: spaces,
      tasks: tasks,
      lifeLogEntries: lifeLogEntries,
      people: people,
      aiHistory: aiHistory,
      aiMemories: aiMemories,
      mailDrafts: mailDrafts,
      companyTemplates: companyTemplates,
      documents: documents,
      projectSources: projectSources,
      projectChats: projectChats,
      webResearchReports: webResearchReports,
      customSkills: customSkills,
      skillSelections: skillSelections,
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
    try Task.checkCancellation()
    let data: Data
    do {
      guard let file = BackupPackageFile.resolve(manifestName, in: packageURL) else { throw BackupError.unreadable }
      data = try Data(contentsOf: file)
    } catch {
      throw BackupError.unreadable
    }

    guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
      throw BackupError.unreadable
    }
    guard (1...currentVersion).contains(manifest.version) else {
      throw BackupError.unsupportedVersion(manifest.version)
    }

    try validateIdentifiers(manifest)
    let skills = manifest.customSkills ?? []
    guard skills.count <= 30, skills.allSatisfy(MemoraSkillMarkdown.valid),
          Set(skills.map(\.id)).count == skills.count,
          (manifest.skillSelections ?? []).count <= 100 else { throw BackupError.unreadable }
    let memories = manifest.aiMemories ?? []
    let drafts = manifest.mailDrafts ?? []
    let templates = manifest.companyTemplates ?? []
    guard memories.count <= 5_000, Set(memories.map(\.id)).count == memories.count,
          memories.allSatisfy({ $0.text.count <= 200 && ($0.revisions?.count ?? 0) <= 30 }),
          drafts.count <= 1_000, Set(drafts.map(\.id)).count == drafts.count,
          drafts.allSatisfy({ draft in draft.body.count <= 100_000 && draft.subject.count <= 500 &&
            draft.recipients.count + draft.cc.count + draft.bcc.count <= 100 &&
            (draft.recipients + draft.cc + draft.bcc).allSatisfy(MailDraft.validAddress) &&
            (draft.provenance?.isValid ?? true) && (draft.provenance.map { $0.workspaceID == draft.workspaceID } ?? true) }),
          (manifest.documents ?? []).allSatisfy({ $0.hasValidRevisions && ($0.provenance?.isValid ?? true)
            && ($0.presentationPlan?.isValid(for: $0.slides) ?? true) }),
          templates.count <= 100, Set(templates.map(\.id)).count == templates.count,
          templates.allSatisfy({ $0.analysis.placeholders.count <= 30 && MediaFiles.isPlainName($0.fileReference)
            && ($0.analysis.presentation?.isValid ?? true) }) else { throw BackupError.unreadable }
    let sources = manifest.projectSources ?? []
    let chats = manifest.projectChats ?? []
    guard Set(sources.map(\.id)).count == sources.count,
          Set(chats.map(\.id)).count == chats.count else { throw BackupError.duplicateIdentifiers }
    let reports = manifest.webResearchReports ?? []
    guard Set(reports.map(\.id)).count == reports.count else { throw BackupError.duplicateIdentifiers }
    guard reports.allSatisfy({ report in
      report.sources.count <= 16 && report.queries.count <= ResearchPlan.maximumSearches && report.query.count <= 600 &&
      Set(report.sources.map(\.id)).count == report.sources.count &&
      report.sources.allSatisfy { source in
        source.text.count <= 8_000 && source.title.count <= 200 &&
        (try? ProjectSourceURL.normalized(source.url.absoluteString).url) == source.url
      }
    }) else { throw BackupError.unreadable }
    let projectIDs = Set(manifest.spaces.map(\.id))
    guard sources.allSatisfy({ $0.projectID.map(projectIDs.contains) ?? true }),
          chats.allSatisfy({ $0.projectID.map(projectIDs.contains) ?? true }) else { throw BackupError.unreadable }
    try ProjectWorkspaceBackup.validate(sources, in: packageURL, additionalNames: manifest.additionalWorkspaceFiles)

    // A record that still holds its photos inline cannot be restored without
    // writing files during the read, so it is refused rather than half-restored.
    guard !manifest.meetings.contains(where: { $0.legacyPhotoData != nil }) else {
      throw BackupError.inlineMediaUnsupported
    }

    // The lists are checked as two kinds, and the two must not share a name: a
    // file cannot be both an audio and a photo.
    let listedAudio = Set(manifest.audioFileNames)
    let listedPhotos = Set(manifest.photoFileNames)
    if let shared = listedAudio.intersection(listedPhotos).sorted().first {
      throw BackupError.conflictingMedia(shared)
    }
    for name in listedAudio where !MediaFiles.isPlainName(name) {
      throw BackupError.unsafeReference(name)
    }
    for name in listedPhotos where !MediaFiles.isPlainName(name) {
      throw BackupError.unsafeReference(name)
    }

    // Every reference a record holds is checked against its own kind, so an
    // audio cannot be satisfied by a photo of the same name, and vice versa.
    let referenced = try referencedMedia(manifest)
    var missing: [String] = []
    for name in referenced.requiredAudio where !listedAudio.contains(name) {
      missing.append(name)
    }
    for name in referenced.requiredPhotos where !listedPhotos.contains(name) {
      missing.append(name)
    }

    // Every listed file must be there, and must be a regular file: a folder or a
    // symlink is not media this app will copy into place.
    for name in listedAudio where BackupPackageFile.resolve(name, folder: mediaFolderName, in: packageURL) == nil {
      missing.append(name)
    }
    for name in listedPhotos where BackupPackageFile.resolve(name, folder: mediaFolderName, in: packageURL) == nil {
      missing.append(name)
    }
    guard missing.isEmpty else { throw BackupError.missingMedia(Array(Set(missing)).sorted()) }

    return manifest
  }

  /// Verifies the package's media into a staging area, then moves it into the
  /// app's folders. Nothing lands in the app until every file is present, an
  /// existing file is never replaced, and a failure part-way takes back only the
  /// files this restore created. Returns those files so a later step can undo it.
  @discardableResult
  static func install(
    mediaFrom packageURL: URL,
    manifest: Manifest
  ) throws -> [(name: String, isAudio: Bool)] {
    let fileManager = FileManager.default
    let staging = fileManager.temporaryDirectory
      .appendingPathComponent("MemoraRestore-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }

    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    } catch {
      throw BackupError.mediaInstallFailed([staging.lastPathComponent])
    }

    // Named once per kind, so a repeated name cannot stage the same file twice.
    let audioNames = Set(manifest.audioFileNames)
    let photoNames = Set(manifest.photoFileNames)
    if let shared = audioNames.intersection(photoNames).sorted().first {
      throw BackupError.conflictingMedia(shared)
    }

    // 1. Stage every file, checking that it really arrives as a regular file.
    var staged: [(name: String, url: URL, isAudio: Bool)] = []
    for (names, isAudio) in [(audioNames.sorted(), true), (photoNames.sorted(), false)] {
      for name in names {
        try Task.checkCancellation()
        guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
        guard let source = BackupPackageFile.resolve(name, folder: mediaFolderName, in: packageURL) else {
          throw BackupError.mediaInstallFailed([name])
        }
        let destination = staging.appendingPathComponent(name)
        guard copy(from: source, to: destination), BackupPackageFile.resolve(name, in: staging) != nil else {
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

    var installed: [(name: String, isAudio: Bool)] = []
    func rollBack() {
      for entry in installed {
        let folder = entry.isAudio ? MediaFiles.directory : MediaFiles.photosDirectory
        try? fileManager.removeItem(at: folder.appendingPathComponent(entry.name))
      }
    }
    for file in staged {
      if Task.isCancelled { rollBack(); throw CancellationError() }
      let folder = file.isAudio ? MediaFiles.directory : MediaFiles.photosDirectory
      let destination = folder.appendingPathComponent(file.name)
      // A same-named file on the device is a conflict, not a replacement, so
      // nothing of the person's own is ever destroyed by a restore.
      guard !fileManager.fileExists(atPath: destination.path) else {
        rollBack()
        throw BackupError.mediaConflict(file.name)
      }
      do {
        try fileManager.moveItem(at: file.url, to: destination)
        installed.append((file.name, file.isAudio))
      } catch {
        rollBack()
        throw BackupError.mediaInstallFailed([file.name])
      }
    }
    return installed
  }

  /// Removes exactly the files a restore put in place, so a later failure leaves
  /// the device as it was without touching anything that was already there.
  static func removeInstalledMedia(_ files: [(name: String, isAudio: Bool)]) {
    for file in files where MediaFiles.isPlainName(file.name) {
      let folder = file.isAudio ? MediaFiles.directory : MediaFiles.photosDirectory
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(file.name))
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
    var audioNames: Set<String> = []

    func addAudio(_ url: URL?) throws {
      guard let url else { return }
      guard let name = MediaFiles.reference(for: url) else {
        throw BackupError.unsafeReference(url.lastPathComponent)
      }
      guard FileManager.default.fileExists(atPath: url.path) else {
        missing.append(name)
        return
      }
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
        throw BackupError.unsafeReference(name)
      }
      if audioNames.insert(name).inserted {
        plan.required.append(MediaFile(name: name, url: url, isAudio: true))
      }
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
      // A record still holding inline photos would be refused on restore, so the
      // export says so instead of writing a package that cannot come back.
      if meeting.legacyPhotoData != nil {
        throw BackupError.inlineMediaUnsupported
      }
      if let url = meeting.audioURL {
        try addAudio(url)
      } else if let raw = meeting.rawAudioReference {
        let candidate = raw.hasPrefix("/") ? URL(fileURLWithPath: raw) : MediaFiles.resolve(raw)
        guard let url = candidate else { throw BackupError.unsafeReference(raw) }
        try addAudio(url)
      }
      for name in meeting.originalAudioFileNames {
        guard MediaFiles.isPlainName(name), let url = MediaFiles.resolve(name) else {
          throw BackupError.unsafeReference(name)
        }
        try addAudio(url)
      }
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
      for name in meeting.originalAudioFileNames {
        guard manifest.version >= 3 else { throw BackupError.unreadable }
        guard MediaFiles.isPlainName(name) else { throw BackupError.unsafeReference(name) }
        audio.insert(name)
      }
      if let raw = meeting.rawAudioReference {
        // The raw stored value is checked, not the resolved URL: an unsafe
        // reference resolves to nil and would otherwise slip through unnoticed.
        if raw.hasPrefix("/") {
          guard let name = MediaFiles.reference(for: URL(fileURLWithPath: raw)) else {
            throw BackupError.unsafeReference(raw)
          }
          audio.insert(name)
        } else {
          guard MediaFiles.isPlainName(raw) else { throw BackupError.unsafeReference(raw) }
          audio.insert(raw)
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
          !hasDuplicates((manifest.documents ?? []).map(\.id)),
          !hasDuplicates(manifest.aiHistory.map(\.id)) else {
      throw BackupError.duplicateIdentifiers
    }
  }
}
