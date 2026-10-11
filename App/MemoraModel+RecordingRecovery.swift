import Foundation

extension MemoraModel {
  /// The minimum needed to bring back a recording the app did not get to save.
  /// The id identifies the record this recording will become, so an interrupted
  /// recovery that is tried again finds the record it already made instead of
  /// making a second one. Drafts written before the id was stored have none, and
  /// are given one on the first load.
  struct RecordingDraft: Codable {
    var id: UUID?
    var fileName: String
    var title: String
    var note: String
    var startedAt: Date
    var spaceID: UUID? = nil
    var markers: [RecordingMarker]? = nil
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
  /// awaiting transcription, or, when no audio survived, the note becomes a
  /// memo. Recording is never restarted on its own.
  func recoverRecordingDraft() async {
    guard let draft = recordingDraft else { return }
    // A store that could not be read must not be written over, so recovery waits
    // for the next healthy launch instead of adding records that cannot be saved.
    guard !isStoreProtected else { return }

    let id = draft.id ?? UUID()
    // A recovery that already stored the record but was cut off before the draft
    // was removed must not make a second one.
    if meetings.contains(where: { $0.id == id }) || lifeLogEntries.contains(where: { $0.id == id }) {
      clearRecordingDraft()
      return
    }

    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let audioURL = MediaFiles.resolve(draft.fileName),
          FileManager.default.fileExists(atPath: audioURL.path) else {
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

    let duration = await MediaFiles.duration(of: audioURL) ?? 1
    var meeting = Meeting(
      id: id,
      title: title.isEmpty ? "復旧した録音" : title,
      createdAt: draft.startedAt,
      duration: duration,
      source: .recording,
      status: .waitingForTranscription,
      summary: "アプリが中断する前に録音していた音声を復旧しました。文字起こしを開始できます。",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: [],
      spaceID: ProjectFiling.existingProject(draft.spaceID, in: spaces),
      audioURL: audioURL
    )
    meeting.notes = note
    meeting.recordingMarkers = RecordingMarker.validated(draft.markers ?? [], duration: duration)
    meetings.insert(meeting, at: 0)

    lifeLogEntries.insert(
      LifeLogEntry(
        id: id,
        createdAt: draft.startedAt,
        title: meeting.title,
        summary: "中断前に録音していた音声を復旧しました。",
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
    recordingDraft = nil
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
    await persistBatchAsync({
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(meetings)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))
      ]
    }, removing: [StorageKey.recordingDraft])
  }
}
