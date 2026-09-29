import Foundation
import UniformTypeIdentifiers

extension MemoraModel {
  /// Copies an audio file into the app, checks that it can actually be played,
  /// and records its real length. The file work runs off the main actor, and a
  /// failed import leaves nothing behind.
  /// `source` marks what the audio is. A phone call is transcribed and turned
  /// into a call memo straight away, since that is what bringing one in asks for.
  func importAudio(from sourceURL: URL, source: MeetingSource = .importFile) async {
    guard !isImporting else { return }
    isImporting = true
    importProgress = nil
    importErrorMessage = nil

    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
    let outcome = await Task.detached(priority: .userInitiated) { () -> ImportOutcome in
      let directory = MediaFiles.directory
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Work under a temporary name so a failure cannot leave a half file.
        let working = directory.appendingPathComponent("importing-\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: sourceURL, to: working)

        guard let duration = await MediaFiles.duration(of: working) else {
          try? FileManager.default.removeItem(at: working)
          return .unreadable
        }

        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: working, to: destination)
        return .imported(destination, duration)
      } catch {
        return .failed
      }
    }.value

    let title = sourceURL.deletingPathExtension().lastPathComponent
    switch outcome {
    case .imported(let destination, let duration):
      let fallbackTitle = source == .phoneCall ? "通話" : "インポートした音声"
      let meeting = Meeting(
        id: UUID(),
        title: title.isEmpty ? fallbackTitle : title,
        createdAt: .now,
        duration: duration,
        source: source,
        status: .waitingForTranscription,
        summary: "音声を保存しました。必要な時に文字起こしを開始できます。",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: [],
        spaceID: nil,
        audioURL: destination
      )
      meetings.insert(meeting, at: 0)
      persistMeetings()
      // No sheet is closing here, so the offer can be shown right away.
      noteRealSaveForSampleCleanup()
      presentPendingSampleCleanupIfNeeded()
      importProgress = 1
      isImporting = false
      selectedTab = .files
      libraryPath = [.meeting(meeting.id)]
      if source == .phoneCall {
        startTranscription(meeting.id)
      }
    case .unreadable:
      isImporting = false
      importErrorMessage = "この音声は再生できないため取り込めませんでした。別のファイルをお試しください。"
    case .failed:
      isImporting = false
      importErrorMessage = "音声を読み込めませんでした。ファイル形式と空き容量を確認してください。"
    }
  }

  private enum ImportOutcome {
    case imported(URL, TimeInterval)
    case unreadable
    case failed
  }

  func importAIAttachment(from sourceURL: URL) throws -> AIAttachment {
    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("AIAttachments", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(sourceURL.pathExtension)
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return AIAttachment(id: UUID(), name: sourceURL.lastPathComponent, url: destination)
  }

  func importAIPhoto(data: Data, fileExtension: String) throws -> AIAttachment {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let directory = base.appendingPathComponent("AIAttachments", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safeExtension = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
    let resolvedExtension = safeExtension.isEmpty ? "jpg" : safeExtension
    let fileName = "写真-\(UUID().uuidString.prefix(8)).\(resolvedExtension)"
    let destination = directory.appendingPathComponent(fileName)
    try data.write(to: destination, options: .atomic)
    return AIAttachment(id: UUID(), name: fileName, url: destination)
  }

  /// Imports an audio file handed to the app. While recording, it waits, so the
  /// recording is not interrupted; it is taken in once the recording ends.
  private func receiveImportedFile(_ url: URL) async {
    guard Self.isAudioFile(url) else { return }
    if isRecording {
      pendingImportURLs.append(url)
      inFlightImportURLs.insert(url)
      pendingImportNotice = "録音が終わったら取り込みます。"
      return
    }
    await importAndCleanUp(url)
  }

  /// Takes in the audio files that arrived during a recording, in order.
  func processPendingImports() async {
    guard !pendingImportURLs.isEmpty, !isRecording else { return }
    let urls = pendingImportURLs
    pendingImportURLs = []
    for url in urls {
      await importAndCleanUp(url)
    }
  }

  /// Imports a file and then removes the copy iOS made in the app's Inbox.
  /// A file the person picked themselves does not sit there and is left alone.
  private func importAndCleanUp(_ url: URL) async {
    inFlightImportURLs.insert(url)
    await importAudio(from: url)
    removeInboxCopyIfNeeded(url)
    inFlightImportURLs.remove(url)
  }

  private func removeInboxCopyIfNeeded(_ url: URL) {
    let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Inbox", isDirectory: true)
      .standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(inbox + "/") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// The audio files sitting in the Inbox, e.g. an import cut short by the app
  /// being closed.
  private func inboxAudioURLs() -> [URL] {
    let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Inbox", isDirectory: true)
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: inbox,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []
    let inFlight = inFlightImportURLs.union(pendingImportURLs)
    return contents.filter { url in
      guard Self.isAudioFile(url) else { return false }
      if inFlight.contains(url) { return false }
      // A file handed over just now is still arriving, not left behind.
      if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
         Date.now.timeIntervalSince(modified) < 60 {
        return false
      }
      return true
    }
  }

  /// Looks for audio left in the Inbox and, if any, asks what to do with it.
  func scanInboxForAudio() {
    guard !isRecording else { return }
    let count = inboxAudioURLs().count
    pendingInboxCount = count > 0 ? count : nil
  }

  func importInboxAudio() async {
    let urls = inboxAudioURLs()
    pendingInboxCount = nil
    for url in urls {
      await importAudio(from: url)
      removeInboxCopyIfNeeded(url)
    }
  }

  func discardInboxAudio() {
    for url in inboxAudioURLs() {
      try? FileManager.default.removeItem(at: url)
    }
    pendingInboxCount = nil
  }

  private static func isAudioFile(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .audio)
  }

  func handle(_ url: URL) async {
    // A file opened with "Open in Memora" (Voice Memos, PLAUD, a share sheet)
    // arrives as a file URL and is imported as audio.
    if url.isFileURL {
      await receiveImportedFile(url)
      return
    }

    guard url.scheme == "memora" else { return }

    if url.host == "meeting" {
      guard let id = UUID(uuidString: url.lastPathComponent) else { return }
      // A link is to a record on this device; it resolves nowhere else, so a
      // missing record is explained instead of opening an empty screen.
      if meeting(id: id) != nil {
        selectedTab = .files
        libraryPath = [.meeting(id)]
      } else if trashedRecords.contains(where: { $0.meeting.id == id }) {
        missingRecordNotice = MissingRecordNotice(
          message: "この記録は「最近削除した項目」にあります。元に戻すか確認してください。",
          offersTrash: true
        )
      } else {
        missingRecordNotice = MissingRecordNotice(
          message: "この端末にこの記録はありません。リンクは記録のある端末でのみ開けます。バックアップから復元できる場合があります。",
          offersTrash: false
        )
      }
      return
    }

    selectedTab = .files
    libraryPath = []
    if url.host == "capture" {
      await startCapture()
    } else if url.host == "recording", isRecording {
      isCapturePresented = true
    }
  }
}
