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
  @discardableResult
  func updateTranscriptSegment(meetingID: UUID, segmentID: UUID, text: String) async -> Bool {
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == meetingID }),
          let segmentIndex = meetings[meetingIndex].transcript.firstIndex(where: { $0.id == segmentID }) else { return false }
    return await commitMeetingChange(meetingID) {
      $0.transcript[segmentIndex].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  @discardableResult
  func updateMeeting(_ id: UUID, change: (inout Meeting) -> Void) -> Bool {
    guard !Task.isCancelled, !isRestoring, currentTeamID == nil, isStoreWritable(),
          let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    var updated = meetings[index]
    change(&updated)
    guard updated != meetings[index] else { return true }
    var candidate = meetings
    candidate[index] = updated
    // Callers use success to start follow-up work or discard their drafts.
    // Publish only the snapshot that actually reached the ordered store.
    guard persistBatch(meetings: candidate, { [] }) else { return false }
    meetingSearchTexts.removeValue(forKey: id)
    meetings = candidate
    return true
  }

  /// Applies an edit and waits for it to be stored, reporting whether it landed.
  /// Used where a draft is cleared afterwards, so the draft is kept when the
  /// record could not be written.
  @discardableResult
  func commitMeetingChange(_ id: UUID, change: (inout Meeting) -> Void) async -> Bool {
    guard !Task.isCancelled, !isRestoring, currentTeamID == nil, isStoreWritable(),
          let index = meetings.firstIndex(where: { $0.id == id }) else { return false }
    let original = meetings[index]
    let generation = aiWorkspaceGeneration
    var updated = original
    change(&updated)
    // Encoding can outlast another edit or a processing tick. Rebuild from the
    // latest collection, but never replay the caller's mutation closure.
    for _ in 0..<3 {
      guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
            aiWorkspaceGeneration == generation, let currentIndex = meetings.firstIndex(where: { $0.id == id }) else { return false }
      guard let rebased = Self.rebaseMeetingEdit(original: original, updated: updated, current: meetings[currentIndex]) else {
        break
      }
      let base = meetings
      var candidate = base
      candidate[currentIndex] = rebased
      guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
            aiWorkspaceGeneration == generation else { return false }
      guard meetings == base else { continue }
      // Only the rows that changed are encoded, so the retry loop no longer
      // encodes the whole collection off the main actor first.
      guard persistBatch(meetings: candidate, { [] }) else { return false }
      meetingSearchTexts.removeValue(forKey: id)
      meetings = candidate
      return true
    }
    persistenceFailureMessage = "記録が更新されたため保存を止めました。書きかけの内容を確認して、もう一度保存してください。"
    return false
  }

  private static func rebaseMeetingEdit(original: Meeting, updated: Meeting, current: Meeting) -> Meeting? {
    guard original.id == updated.id, original.id == current.id else { return nil }
    // Inline editors author these fields. Keep newer processing state and
    // unrelated edits; unknown mutation shapes retain the strict whole-record gate.
    var remainder = updated
    remainder.notes = original.notes
    remainder.summary = original.summary
    remainder.transcript = original.transcript
    guard remainder == original else { return current == original ? updated : nil }
    var result = current
    if updated.notes != original.notes {
      guard current.notes == original.notes || current.notes == updated.notes else { return nil }
      result.notes = updated.notes
    }
    if updated.summary != original.summary {
      guard current.summary == original.summary || current.summary == updated.summary else { return nil }
      result.summary = updated.summary
    }
    if updated.transcript != original.transcript {
      guard current.transcript == original.transcript || current.transcript == updated.transcript else { return nil }
      result.transcript = updated.transcript
    }
    return result
  }

  /// Changes a record in memory only, for passing state such as a progress
  /// label. Writing every record (transcripts included) for each tick is what
  /// made a streaming summary slow the app down; the finished result is saved.
  func updateMeetingTransiently(_ id: UUID, change: (inout Meeting) -> Void) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    isApplyingTransientMeetingUpdate = true
    defer { isApplyingTransientMeetingUpdate = false }
    change(&meetings[index])
  }
}
