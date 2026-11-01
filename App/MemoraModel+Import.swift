import Foundation
import UniformTypeIdentifiers

extension MemoraModel {
  @discardableResult
  func importPickedAudio(from url: URL, context: LocalImportContext?) async -> UUID? {
    // A missing picker context must not fall through to importAudio's fresh
    // context for programmatic imports and silently accept another workspace.
    guard let context, context.isCurrent(in: self) else {
      importErrorMessage = String(localized: "保存先の状態が変わったため取り込みませんでした。もう一度ファイルを選択してください。")
      return nil
    }
    return await importAudio(from: url, spaceID: context.projectID, importContext: context)
  }

  /// Copies an audio file into the app, checks that it can actually be played,
  /// and records its real length. The file work runs off the main actor, and a
  /// failed import leaves nothing behind.
  @discardableResult
  func importAudio(from sourceURL: URL, spaceID: UUID? = nil, importContext: LocalImportContext? = nil) async -> UUID? {
    guard !isImporting, !isRestoring, isStoreWritable() else { return nil }
    guard spaceID == nil || ProjectFiling.existingProject(spaceID, in: spaces) != nil else {
      importErrorMessage = "保存先のプロジェクトが見つかりません。開き直してください。"
      return nil
    }
    guard let context = importContext ?? LocalImportContext(projectID: spaceID, in: self),
          context.projectID == spaceID, context.isCurrent(in: self) else { return nil }
    isImporting = true
    importProgress = nil
    importErrorMessage = nil
    defer { isImporting = false }

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
        defer { try? FileManager.default.removeItem(at: working) }
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
      let meeting = Meeting(
        id: UUID(),
        title: title.isEmpty ? "インポートした音声" : title,
        createdAt: .now,
        duration: duration,
        source: .importFile,
        status: .waitingForTranscription,
        summary: "",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: [],
        spaceID: ProjectFiling.existingProject(spaceID, in: spaces),
        audioURL: destination
      )
      let candidate = [meeting] + meetings
      guard context.isCurrent(in: self, allowsRemovedProject: true),
            persistNow(candidate, forKey: StorageKey.meetings) else {
        if !MediaFiles.delete(destination) {
          deletionFailureMessage = "保存できなかったインポート音声の削除に失敗しました。"
        }
        importErrorMessage = "音声を保存できませんでした。元のファイルは変更していません。空き容量を確認して、もう一度取り込んでください。"
        return nil
      }
      meetings = candidate
      if spaceID != nil, meeting.spaceID == nil {
        projectFilingNotice = "取り込み中に保存先のプロジェクトが削除されたため、音声は未分類のファイルに保存しました。"
      }
      // No sheet is closing here, so the offer can be shown right away.
      noteRealSaveForSampleCleanup()
      presentPendingSampleCleanupIfNeeded()
      importProgress = 1
      isImporting = false
      openSavedMeeting(meeting.id)
      startTranscription(meeting.id, onDeviceOnly: true, automaticallySummarize: true)
      return meeting.id
    case .unreadable:
      isImporting = false
      importErrorMessage = "この音声は再生できないため取り込めませんでした。別のファイルをお試しください。"
      return nil
    case .failed:
      isImporting = false
      importErrorMessage = "音声を読み込めませんでした。ファイル形式と空き容量を確認してください。"
      return nil
    }
  }

  private enum ImportOutcome {
    case imported(URL, TimeInterval)
    case unreadable
    case failed
  }

  func importAIAttachment(from sourceURL: URL) async throws -> AIAttachment {
    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let receipt = try await AIAttachmentFiles.shared.copy(sourceURL)
    return AIAttachment(id: UUID(), name: sourceURL.lastPathComponent, url: try AIAttachmentFiles.url(receipt.reference))
  }

  func importAIPhoto(data: Data, fileExtension: String) async throws -> AIAttachment {
    let safeExtension = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
    let resolvedExtension = safeExtension.isEmpty ? "jpg" : safeExtension
    let reference = try await AIAttachmentFiles.shared.write(data, extension: resolvedExtension)
    return AIAttachment(id: UUID(), name: "写真.\(resolvedExtension)", url: try AIAttachmentFiles.url(reference))
  }

  /// Imports an audio file handed to the app. While recording, it waits, so the
  /// recording is not interrupted; it is taken in once the recording ends.
  private func receiveImportedFile(_ url: URL) async {
    guard let context = LocalImportContext(projectID: visibleProjectID, in: self) else { return }
    if isRecording {
      pendingImportURLs.append(url)
      pendingInformationImportContexts[url] = context
      inFlightImportURLs.insert(url)
      pendingImportNotice = "録音が終わったら取り込みます。"
      return
    }
    await importAndCleanUp(url, context: context)
  }

  /// Takes in the audio files that arrived during a recording, in order.
  func processPendingImports() async {
    guard !pendingImportURLs.isEmpty, !isRecording else { return }
    let urls = pendingImportURLs
    pendingImportURLs = []
    for url in urls {
      let context = pendingInformationImportContexts.removeValue(forKey: url)
      await importAndCleanUp(url, context: context)
    }
  }

  /// Imports a file and then removes the copy iOS made in the app's Inbox.
  /// A file the person picked themselves does not sit there and is left alone.
  private func importAndCleanUp(_ url: URL, context: LocalImportContext?) async {
    inFlightImportURLs.insert(url)
    if await importInformationFile(url, context: context) != nil { removeInboxCopyIfNeeded(url) }
    inFlightImportURLs.remove(url)
  }

  private func removeInboxCopyIfNeeded(_ url: URL) {
    let inbox = AudioInbox.directory.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(inbox + "/") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// The audio files sitting in the Inbox, e.g. an import cut short by the app
  /// being closed.
  private func inboxAudioURLs() -> [URL] {
    let inbox = AudioInbox.directory
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: inbox,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []
    let inFlight = inFlightImportURLs.union(pendingImportURLs)
    return contents.filter { url in
      guard !url.hasDirectoryPath else { return false }
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
      if await importInformationFile(url, context: LocalImportContext(in: self)) != nil { removeInboxCopyIfNeeded(url) }
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

    guard url.scheme?.lowercased() == "memora" else { return }
    if url.host?.lowercased() == "source" {
      openExternalSourceCitation(url)
      return
    }
    if let link = MemoraAppLink(url: url) {
      openSystemDestination(link)
      return
    }

    if url.host == "task" {
      guard let id = UUID(uuidString: url.lastPathComponent), tasks.contains(where: { $0.id == id }) else { return }
      openTask(id)
      return
    }

    if url.host == "meeting" {
      guard let id = UUID(uuidString: url.lastPathComponent) else { return }
      // A link is to a record on this device; it resolves nowhere else, so a
      // missing record is explained instead of opening an empty screen.
      if meeting(id: id) != nil {
        selectedTab = .library
        librarySection = .files
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

    selectedTab = .library
    librarySection = .files
    libraryPath = []
    if url.host == "capture" {
      await startCapture()
    } else if url.host == "recording", isRecording {
      isCapturePresented = true
    }
  }
}
