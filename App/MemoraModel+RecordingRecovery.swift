import Foundation

extension MemoraModel {
  /// The minimum needed to bring back a recording the app did not get to save.
  /// The id identifies the record this recording will become, so an interrupted
  /// recovery that is tried again finds the record it already made instead of
  /// making a second one. Drafts written before the id was stored have none, and
  /// are given one on the first load.
  struct RecordingDraft: Codable, Equatable {
    var id: UUID?
    var fileName: String
    var title: String
    var note: String
    var startedAt: Date
    var spaceID: UUID? = nil
    var markers: [RecordingMarker]? = nil
    var audioManifest: RecordingAudioManifest? = nil
  }

  /// Writes what a running recording would need if the app stopped now.
  func persistRecordingDraft() {
    guard let recordingDraft else {
      try? RecordStore.remove(StorageKey.recordingDraft)
      return
    }
    persistInBackground(recordingDraft, forKey: StorageKey.recordingDraft)
  }

  /// Brings back a recording that was interrupted: its audio becomes a record
  /// awaiting transcription only when its duration can be read. Unverified
  /// audio keeps its file with an error; a missing file leaves a memo instead.
  /// Recording is never restarted on its own.
  func recoverRecordingDraft() async {
    guard !isRecoveringRecordingDraft, !isRecording, !isPreparingCapture,
          !isSavingCapture, !hasUnsavedRecording, !isRestoring, !Task.isCancelled,
          let draft = recordingDraft else { return }
    // A store that could not be read must not be written over, so recovery waits
    // for the next healthy launch instead of adding records that cannot be saved.
    guard !isStoreProtected else { return }
    isRecoveringRecordingDraft = true
    defer { isRecoveringRecordingDraft = false }
    let workspaceGeneration = aiWorkspaceGeneration

    let id = draft.id ?? draft.audioManifest?.recordingID ?? UUID()
    guard draft.audioManifest.map({ $0.isValid(for: id, activeFileName: draft.fileName) }) ?? true else {
      recordingErrorMessage = RecordingAudioValidation.manifestNotice
      return
    }
    // A recovery that already stored the record but was cut off before the draft
    // was removed must not make a second one.
    if meetings.contains(where: { $0.id == id }) || lifeLogEntries.contains(where: { $0.id == id }) {
      if let manifest = draft.audioManifest {
        guard let saved = meetings.first(where: { $0.id == id }),
              saved.recordingAudioManifest?.preservesTimeline(of: manifest) == true,
              Set(manifest.fileNames).isSubset(of: Set(saved.originalAudioFileNames)) else {
          recordingErrorMessage = RecordingAudioValidation.manifestNotice
          return
        }
      }
      clearRecordingDraft()
      return
    }

    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

    let audioURL = MediaFiles.resolve(draft.fileName)
    if draft.audioManifest == nil && (audioURL == nil || !FileManager.default.fileExists(atPath: audioURL!.path)) {
      // With no audio, the note becomes a memo. The memo and the draft removal
      // are one commit, so a stop in the middle leaves one or the other. When
      // there is nothing worth keeping, the draft is simply removed.
      if note.isEmpty {
        clearRecordingDraft()
      } else if addLifeLogEntry(
        id: id,
        kind: .memo,
        title: title.isEmpty ? "復旧したメモ" : title,
        summary: note,
        createdAt: draft.startedAt,
        photoData: nil,
        eventDate: nil,
        locationName: nil,
        removingDraft: StorageKey.recordingDraft
      ) {
        clearRecordingDraft(alreadyRemoved: true)
      }
      return
    }

    let inspection = await inspectRecordingDraft(draft, legacyURL: audioURL)
    guard !Task.isCancelled, !isStoreProtected, !isRestoring,
          !isRecording, !isPreparingCapture, !isSavingCapture,
          recordingDraft == draft, aiWorkspaceGeneration == workspaceGeneration,
          !meetings.contains(where: { $0.id == id }),
          !lifeLogEntries.contains(where: { $0.id == id }) else { return }
    let duration = inspection.duration
    // Zero represents an unverified duration, not an invented one-second clip.
    // Keep valid markers without clipping them to that unknown endpoint.
    let unreadableNotice = inspection.notice
    var meeting = Meeting(
      id: id,
      title: title.isEmpty ? "復旧した録音" : title,
      createdAt: draft.startedAt,
      duration: duration ?? 0,
      source: .recording,
      status: inspection.canProcess ? .waitingForTranscription : .failed(unreadableNotice),
      summary: !inspection.canProcess ? unreadableNotice
        : "アプリが中断する前に録音していた音声を復旧しました。文字起こしを開始できます。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: ProjectFiling.existingProject(draft.spaceID, in: spaces),
      audioURL: inspection.playbackURL
    )
    meeting.originalAudioFileNames = draft.audioManifest?.fileNames ?? []
    meeting.recordingAudioManifest = inspection.manifest
    meeting.notes = note
    meeting.recordingMarkers = RecordingMarker.validated(draft.markers ?? [], duration: duration)
    meetings.insert(meeting, at: 0)

    lifeLogEntries.insert(
      LifeLogEntry(
        id: id,
        createdAt: draft.startedAt,
        title: meeting.title,
        summary: !inspection.canProcess ? "中断前の録音の保存情報を保持しました。音声ファイルを確認してください。"
          : "中断前に録音していた音声を復旧しました。",
        source: .iphone,
        meetingID: meeting.id
      ),
      at: 0
    )

    // The recovered record, its journal entry and the draft removal are written
    // together, so a stop in the middle leaves either all of it or none of it.
    let stored = await commitRecordingSave()
    guard stored else {
      // Put the in-memory lists back so nothing points at a record that was not
      // written, and keep the draft for the next attempt.
      meetings.removeAll { $0.id == id }
      lifeLogEntries.removeAll { $0.id == id }
      return
    }
    if recordingDraft == draft { recordingDraft = nil }
  }

  /// Recovery owns the old draft until its record is committed. A new capture
  /// must not replace it while media inspection or SQLite is still suspended.
  func resolvePendingRecordingBeforeCapture() async -> Bool {
    if recordingDraft != nil { await recoverRecordingDraft() }
    guard recordingDraft == nil, !isRecoveringRecordingDraft else {
      recordingErrorMessage = String(localized: "前回の録音を保存できていないため、新しい録音は開始していません。復旧が完了してからもう一度お試しください。",
        comment: "A pending interrupted recording blocks replacement by a new recording")
      return false
    }
    return !isRestoring && !isStoreProtected
  }

  /// Forgets the recording draft and removes its stored copy. `alreadyRemoved`
  /// says a commit has just removed it, so no second removal is needed.
  private func clearRecordingDraft(alreadyRemoved: Bool = false) {
    recordingDraft = nil
    if !alreadyRemoved {
      persistRecordingDraft()
    }
  }

  /// Writes the records and the journal together with the draft's removal, so
  /// a stop in the middle leaves either the saved recording or its draft.
  func commitRecordingSave() async -> Bool {
    await persistBatchAsync(meetings: meetings, {
      [
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))
      ]
    }, removing: [StorageKey.recordingDraft])
  }
}
