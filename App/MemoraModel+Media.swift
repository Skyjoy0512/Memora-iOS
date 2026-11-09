import Foundation

extension MemoraModel {
  /// A removal that still has to happen: the record it belongs to is gone from
  /// the store, but one or more of its files remain on disk.
  struct PendingMediaDeletion: Codable, Identifiable {
    var id: UUID
    var audioReference: String?
    var photoNames: [String]
  }

  func addMeetingPhoto(_ id: UUID, data: Data) {
    guard !Task.isCancelled, !isRestoring, currentTeamID == nil, isStoreWritable(), meeting(id: id) != nil else { return }
    guard let name = MediaFiles.writePhoto(data, thumbnailMaxSide: 400) else {
      persistenceFailureMessage = "写真を保存できませんでした。ストレージの空き容量を確認してください。"
      return
    }
    guard updateMeeting(id, change: { meeting in
      var names = meeting.photoFileNames ?? []
      names.append(name)
      meeting.photoFileNames = names
    }) else {
      deleteMedia(audioURL: nil, photoNames: [name])
      return
    }
  }

  /// Removes a photo from a record. The record is written first and the file is
  /// only removed once that write landed, so a failed save cannot leave the
  /// record pointing at a file that was already erased.
  func removeMeetingPhoto(_ id: UUID, index: Int) {
    guard isStoreWritable() else { return }
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == id }) else { return }

    var candidate = meetings
    var names = candidate[meetingIndex].photoFileNames ?? []
    guard names.indices.contains(index) else { return }
    let removed = names.remove(at: index)
    candidate[meetingIndex].photoFileNames = names.isEmpty ? nil : names
    meetingSearchTexts.removeValue(forKey: id)

    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }

    meetings = candidate
    // The file is registered as a pending removal right away, so it survives the
    // app being stopped during the offer, but it is not deleted until the offer
    // passes: an undo still has a photo to show.
    let pendingDeletionID = registerPendingPhotoDeletion(removed)
    scheduleUndo(
      UndoAction(message: "写真を削除しました") { [weak self] in
        self?.cancelPendingMediaDeletion(pendingDeletionID)
        self?.restoreMeetingPhoto(id, name: removed, at: index)
      } finalize: { [weak self] in
        self?.finalizePendingMediaDeletion(pendingDeletionID)
      }
    )
  }

  /// Remembers a photo file for removal, so letting the app stop mid-offer still
  /// leaves a record that it should be deleted.
  private func registerPendingPhotoDeletion(_ name: String) -> UUID {
    let entry = PendingMediaDeletion(id: UUID(), audioReference: nil, photoNames: [name])
    pendingMediaDeletions.append(entry)
    persistPendingMediaDeletions()
    return entry.id
  }

  /// Drops a registration without deleting the file, for an undo.
  private func cancelPendingMediaDeletion(_ id: UUID) {
    pendingMediaDeletions.removeAll { $0.id == id }
    persistPendingMediaDeletions()
  }

  /// Keep the journal entry until removal succeeds, including across a stop.
  private func finalizePendingMediaDeletion(_ id: UUID) {
    retryPendingMediaDeletions(onlyIDs: [id])
  }

  func pendingDeletions(for meeting: Meeting, includingPhotos: Bool = true) -> [PendingMediaDeletion] {
    var entries = meeting.managedAudioFileNames.map {
      PendingMediaDeletion(id: UUID(), audioReference: $0, photoNames: [])
    }
    if includingPhotos, let photos = meeting.photoFileNames, !photos.isEmpty {
      entries.append(PendingMediaDeletion(id: UUID(), audioReference: nil, photoNames: photos))
    }
    return entries
  }

  /// A queued removal cannot erase a file another live record or draft owns.
  var referencedAudioFileNames: Set<String> {
    var names = Set(meetings.flatMap(\.managedAudioFileNames))
    names.formUnion(trashedRecords.flatMap { $0.meeting.managedAudioFileNames })
    if let draft = recordingDraft, let url = MediaFiles.resolve(draft.fileName),
       let name = MediaFiles.reference(for: url) { names.insert(name) }
    for reference in recordingDraft?.audioManifest?.fileNames ?? [] {
      if let url = MediaFiles.resolve(reference), let name = MediaFiles.reference(for: url) { names.insert(name) }
    }
    return names
  }

  /// Removes a record's audio but keeps its transcript, summary, notes and
  /// tasks. The file waits for the offer to pass, so an undo still has audio.
  func removeMeetingAudio(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = meetings.firstIndex(where: { $0.id == id }),
          meetings[index].hasAudioFiles else { return }

    let original = meetings[index]
    let deletions = pendingDeletions(for: original, includingPhotos: false)
    let pending = pendingMediaDeletions + deletions
    var candidate = meetings
    candidate[index].removeAudioReferences()
    meetingSearchTexts.removeValue(forKey: id)
    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(pending))
      ]
    }
    guard stored else { return }

    meetings = candidate
    pendingMediaDeletions = pending
    let pendingIDs = Set(deletions.map(\.id))
    scheduleUndo(
      UndoAction(message: "音声を削除しました") { [weak self] in
        self?.restoreMeetingAudio([original], cancelling: pendingIDs)
      } finalize: { [weak self] in
        self?.retryPendingMediaDeletions(onlyIDs: pendingIDs)
      }
    )
  }

  private func restoreMeetingAudio(_ originals: [Meeting], cancelling pendingIDs: Set<UUID>) {
    guard isStoreWritable() else { return }
    var candidate = meetings
    for original in originals {
      guard let index = candidate.firstIndex(where: { $0.id == original.id }),
            !candidate[index].hasAudioFiles else { return }
      candidate[index].audioURL = original.audioURL
      candidate[index].rawAudioReference = original.rawAudioReference
      candidate[index].originalAudioFileNames = original.originalAudioFileNames
      candidate[index].recordingAudioManifest = original.recordingAudioManifest
      meetingSearchTexts.removeValue(forKey: original.id)
    }
    let pending = pendingMediaDeletions.filter { !pendingIDs.contains($0.id) }
    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(pending))
      ]
    }
    guard stored else { return }
    meetings = candidate
    pendingMediaDeletions = pending
  }

  /// Removes the audio of every record older than `days`, keeping the rest of
  /// each record. One undo brings all of it back.
  func removeAudio(olderThanDays days: Int) {
    guard isStoreWritable() else { return }
    let cutoff = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    let removed = meetings.filter { $0.hasAudioFiles && $0.createdAt < cutoff }
    guard !removed.isEmpty else { return }

    var candidate = meetings
    let deletions = removed.flatMap { pendingDeletions(for: $0, includingPhotos: false) }
    let pending = pendingMediaDeletions + deletions
    let pendingIDs = Set(deletions.map(\.id))
    for index in candidate.indices where candidate[index].hasAudioFiles && candidate[index].createdAt < cutoff {
      candidate[index].removeAudioReferences()
      meetingSearchTexts.removeValue(forKey: candidate[index].id)
    }

    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(pending))
      ]
    }
    guard stored else { return }
    meetings = candidate
    pendingMediaDeletions = pending
    scheduleUndo(
      UndoAction(message: "\(removed.count)件の音声を削除しました") { [weak self] in
        self?.restoreMeetingAudio(removed, cancelling: pendingIDs)
      } finalize: { [weak self] in
        self?.retryPendingMediaDeletions(onlyIDs: pendingIDs)
      }
    )
  }

  /// Puts a removed photo back at its old position, so undo restores the order.
  private func restoreMeetingPhoto(_ id: UUID, name: String, at index: Int) {
    guard let meetingIndex = meetings.firstIndex(where: { $0.id == id }) else { return }
    var candidate = meetings
    var names = candidate[meetingIndex].photoFileNames ?? []
    names.insert(name, at: min(index, names.count))
    candidate[meetingIndex].photoFileNames = names
    meetingSearchTexts.removeValue(forKey: id)

    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }
    meetings = candidate
  }
}
