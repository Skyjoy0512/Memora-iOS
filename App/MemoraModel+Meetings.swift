import Foundation

extension MemoraModel {
  func renameMeeting(_ id: UUID, title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    updateMeeting(id) { $0.title = trimmed }
  }

  /// Notes and summary come from an editor that keeps a draft; the caller is
  /// told whether the record was stored, and only then is the draft cleared.
  @discardableResult
  func updateMeetingNotes(_ id: UUID, notes: String) async -> Bool {
    await commitMeetingChange(id) { $0.notes = notes }
  }

  @discardableResult
  func updateMeetingSummary(_ id: UUID, summary: String) async -> Bool {
    await commitMeetingChange(id) { $0.summary = summary }
  }

  func updateMeetingList(_ id: UUID, _ keyPath: WritableKeyPath<Meeting, [String]>, items: [String]) {
    updateMeeting(id) { $0[keyPath: keyPath] = items }
  }

  /// Corrects a speaker name. With `appliesToAllSegments` (the default from the
  /// edit sheet) every line still carrying the old name is corrected at once, so
  /// renaming a speaker does not take one tap per line.
  @discardableResult
  func renameSpeaker(
    meetingID: UUID,
    segmentID: UUID,
    name: String,
    appliesToAllSegments: Bool = false
  ) async -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isRestoring, isStoreWritable(),
          let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return false }

    let original = meetings[meetingIndex].transcript[segmentIndex].speaker
    let originalID = meetings[meetingIndex].transcript[segmentIndex].speakerID
    let canGroup = originalID != nil || meetings[meetingIndex].transcript[segmentIndex].speakerIsCertain
    return await commitMeetingChange(meetingID) { record in
      for index in record.transcript.indices {
        let sameSpeaker = originalID.map { record.transcript[index].speakerID == $0 }
          ?? (record.transcript[index].speaker == original)
        if record.transcript[index].id == segmentID || (appliesToAllSegments && canGroup && sameSpeaker) {
          record.transcript[index].speaker = trimmed
          record.transcript[index].speakerIsCertain = true
          record.transcript[index].identificationStatus = .manual
        }
      }
    }
  }

  /// Corrects the body of one transcript segment, leaving the speaker as is.
  func updateTranscriptSegment(meetingID: UUID, segmentID: UUID, text: String) {
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return }
    meetings[meetingIndex].transcript[segmentIndex].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    meetingSearchTexts.removeValue(forKey: meetingID)
    persistMeetings()
  }

  @discardableResult
  func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    meetingSearchTexts.removeValue(forKey: id)
    change(&meetings[index])
    persistMeetings()
    return true
  }

  /// Applies an edit and waits for it to be stored, reporting whether it landed.
  /// Used where a draft is cleared afterwards, so the draft is kept when the
  /// record could not be written.
  @discardableResult
  private func commitMeetingChange(_ id: UUID, change: (inout Meeting) -> Void) async -> Bool {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    meetingSearchTexts.removeValue(forKey: id)
    change(&meetings[index])
    return await persistNowAsync(meetings, forKey: StorageKey.meetings)
  }

  /// Changes a record in memory only, for passing state such as a progress
  /// label. Writing every record (transcripts included) for each tick is what
  /// made a streaming summary slow the app down; the finished result is saved.
  func updateMeetingTransiently(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    change(&meetings[index])
  }
}
