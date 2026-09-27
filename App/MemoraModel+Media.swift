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
    guard let name = MediaFiles.writePhoto(data, thumbnailMaxSide: 400) else {
      persistenceFailureMessage = "写真を保存できませんでした。ストレージの空き容量を確認してください。"
      return
    }
    updateMeeting(id) { meeting in
      var names = meeting.photoFileNames ?? []
      names.append(name)
      meeting.photoFileNames = names
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

  /// Runs the removal an offer registered. A file that cannot be removed is
  /// remembered again by `deleteMedia`.
  private func finalizePendingMediaDeletion(_ id: UUID) {
    guard let entry = pendingMediaDeletions.first(where: { $0.id == id }) else { return }
    cancelPendingMediaDeletion(id)
    let audioURL = entry.audioReference.flatMap { MediaFiles.resolve($0) }
    deleteMedia(audioURL: audioURL, photoNames: entry.photoNames)
  }

  /// Remembers an audio file for removal, so letting the app stop mid-offer still
  /// leaves a record that it should be deleted.
  private func registerPendingAudioDeletion(_ url: URL) -> UUID {
    let entry = PendingMediaDeletion(
      id: UUID(),
      audioReference: MediaFiles.reference(for: url),
      photoNames: []
    )
    pendingMediaDeletions.append(entry)
    persistPendingMediaDeletions()
    return entry.id
  }

  /// Removes a record's audio but keeps its transcript, summary, notes and
  /// tasks. The file waits for the offer to pass, so an undo still has audio.
  func removeMeetingAudio(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = meetings.firstIndex(where: { $0.id == id }),
          let url = meetings[index].audioURL else { return }

    var candidate = meetings
    candidate[index].audioURL = nil
    meetingSearchTexts.removeValue(forKey: id)
    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }

    meetings = candidate
    let pendingDeletionID = registerPendingAudioDeletion(url)
    scheduleUndo(
      UndoAction(message: "音声を削除しました") { [weak self] in
        self?.cancelPendingMediaDeletion(pendingDeletionID)
        self?.restoreMeetingAudio(id, url: url)
      } finalize: { [weak self] in
        self?.finalizePendingMediaDeletion(pendingDeletionID)
      }
    )
  }

  private func restoreMeetingAudio(_ id: UUID, url: URL) {
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
    var candidate = meetings
    candidate[index].audioURL = url
    meetingSearchTexts.removeValue(forKey: id)
    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }
    meetings = candidate
  }

  /// Removes the audio of every record older than `days`, keeping the rest of
  /// each record. One undo brings all of it back.
  func removeAudio(olderThanDays days: Int) {
    guard isStoreWritable() else { return }
    let cutoff = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
    let removed = meetings.filter { $0.audioURL != nil && $0.createdAt < cutoff }
    guard !removed.isEmpty else { return }

    var candidate = meetings
    var pendingIDs: [UUID] = []
    var restorable: [(id: UUID, url: URL)] = []
    for index in candidate.indices where candidate[index].audioURL != nil && candidate[index].createdAt < cutoff {
      guard let url = candidate[index].audioURL else { continue }
      pendingIDs.append(registerPendingAudioDeletion(url))
      restorable.append((candidate[index].id, url))
      candidate[index].audioURL = nil
      meetingSearchTexts.removeValue(forKey: candidate[index].id)
    }

    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else {
      pendingIDs.forEach { cancelPendingMediaDeletion($0) }
      return
    }
    meetings = candidate
    scheduleUndo(
      UndoAction(message: "\(restorable.count)件の音声を削除しました") { [weak self] in
        pendingIDs.forEach { self?.cancelPendingMediaDeletion($0) }
        for entry in restorable {
          self?.restoreMeetingAudio(entry.id, url: entry.url)
        }
      } finalize: { [weak self] in
        pendingIDs.forEach { self?.finalizePendingMediaDeletion($0) }
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
