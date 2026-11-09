import Foundation

extension MemoraModel {
  /// Moves a record to the trash. Its audio, tasks, and journal entries are kept
  /// so it can be restored exactly, and removed only when the trash is emptied.
  /// The lists are only changed once the write lands, so a failed save leaves
  /// the screen showing what the store actually holds.
  func deleteMeeting(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }

    processing.cancel(id)

    var candidateMeetings = meetings
    var candidateTasks = tasks
    var candidateEntries = lifeLogEntries
    var candidateTrash = trashedRecords

    let removed = candidateMeetings.remove(at: index)
    let removedTasks = candidateTasks.filter { $0.meetingID == id }
    let removedEntries = candidateEntries.filter { $0.meetingID == id }
    candidateTasks.removeAll { $0.meetingID == id }
    candidateEntries.removeAll { $0.meetingID == id }
    candidateTrash.insert(
      TrashedRecord(
        meeting: removed,
        tasks: removedTasks,
        lifeLogEntries: removedEntries,
        deletedAt: .now,
        meetingPosition: index,
        taskPositions: Self.taskPositions(of: removedTasks, in: tasks)
      ),
      at: 0
    )

    // One operation: the record, its tasks, its journal entries, and the trash
    // entry land together or not at all.
    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(candidateTasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.trash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return }

    invalidateProjectEvidence(removedTasks.map { .task($0.id) } + [.meeting(id)])
    meetings = candidateMeetings
    tasks = candidateTasks
    lifeLogEntries = candidateEntries
    trashedRecords = candidateTrash

    let trashID = candidateTrash[0].id
    scheduleUndo(
      UndoAction(message: "「\(removed.displayTitle)」を削除しました") { [weak self] in
        self?.restoreTrashedRecord(trashID, preservingPosition: true)
      } finalize: {}
    )
  }

  /// Moves several records to the trash in one write, so a multi-selection
  /// either lands completely or not at all. Each record keeps its own tasks and
  /// journal entries so it can be restored exactly.
  func deleteMeetings(_ ids: Set<UUID>) {
    guard isStoreWritable() else { return }
    guard !ids.isEmpty else { return }

    let removed = meetings.filter { ids.contains($0.id) }
    guard !removed.isEmpty else { return }
    for meeting in removed {
      processing.cancel(meeting.id)
    }

    var candidateMeetings = meetings
    var candidateTasks = tasks
    var candidateEntries = lifeLogEntries
    var candidateTrash = trashedRecords

    let removedTasks = candidateTasks.filter { $0.meetingID.map(ids.contains) ?? false }
    let removedEntries = candidateEntries.filter { $0.meetingID.map(ids.contains) ?? false }
    candidateMeetings.removeAll { ids.contains($0.id) }
    candidateTasks.removeAll { $0.meetingID.map(ids.contains) ?? false }
    candidateEntries.removeAll { $0.meetingID.map(ids.contains) ?? false }
    candidateTrash.insert(
      contentsOf: removed.map { meeting in
        let meetingTasks = removedTasks.filter { $0.meetingID == meeting.id }
        return TrashedRecord(
          meeting: meeting,
          tasks: meetingTasks,
          lifeLogEntries: removedEntries.filter { $0.meetingID == meeting.id },
          deletedAt: .now,
          meetingPosition: meetings.firstIndex(where: { $0.id == meeting.id }),
          taskPositions: Self.taskPositions(of: meetingTasks, in: tasks)
        )
      },
      at: 0
    )

    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(candidateTasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.trash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return }

    invalidateProjectEvidence(removedTasks.map { .task($0.id) } + removed.map { .meeting($0.id) })
    meetings = candidateMeetings
    tasks = candidateTasks
    lifeLogEntries = candidateEntries
    trashedRecords = candidateTrash

    let trashIDs = candidateTrash.prefix(removed.count).map(\.id)
    scheduleUndo(
      UndoAction(message: "\(removed.count)件の記録を削除しました") { [weak self] in
        for id in trashIDs {
          self?.restoreTrashedRecord(id, preservingPosition: true)
        }
      } finalize: {}
    )
  }

  /// Puts a trashed record back exactly as it was, again only after the write.
  /// The saved position is only used when `preservingPosition` is set, which is
  /// the undo path; a restore from the trash days later goes back by date, since
  /// records added meanwhile would have made the old index wrong.
  func restoreTrashedRecord(_ id: UUID, preservingPosition: Bool = false) {
    guard isStoreWritable() else { return }
    guard let index = trashedRecords.firstIndex(where: { $0.id == id }) else { return }

    var candidateTrash = trashedRecords
    let record = candidateTrash.remove(at: index)
    var candidateMeetings = meetings
    var candidateTasks = tasks
    var candidateEntries = lifeLogEntries
    // Put it back where it was. Undo uses the saved position; a later restore
    // goes by date, which is how the list reads. Records saved before positions
    // existed fall back to date order too.
    let datePosition = candidateMeetings.firstIndex { $0.createdAt < record.meeting.createdAt }
      ?? candidateMeetings.count
    let meetingPosition = preservingPosition ? (record.meetingPosition ?? datePosition) : datePosition
    candidateMeetings.insert(record.meeting, at: min(meetingPosition, candidateMeetings.count))

    // Attached tasks go back to their own positions on undo, in ascending order
    // so the inserts do not shift each other.
    let positions = preservingPosition ? record.taskPositions : nil
    let orderedTasks = record.tasks.enumerated()
      .sorted { lhs, rhs in
        (positions?[lhs.element.id] ?? lhs.offset) < (positions?[rhs.element.id] ?? rhs.offset)
      }
      .map(\.element)
    for task in orderedTasks {
      let position = positions?[task.id] ?? 0
      candidateTasks.insert(task, at: min(position, candidateTasks.count))
    }

    if !record.lifeLogEntries.isEmpty {
      candidateEntries.append(contentsOf: record.lifeLogEntries)
    }

    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(candidateTasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.trash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return }

    trashedRecords = candidateTrash
    meetings = candidateMeetings
    tasks = candidateTasks
    lifeLogEntries = candidateEntries
  }

  /// Where each given task sat in the full list, so a restore can put it back.
  private static func taskPositions(of tasks: [MemoraTask], in all: [MemoraTask]) -> [UUID: Int]? {
    guard !tasks.isEmpty else { return nil }
    var positions: [UUID: Int] = [:]
    for task in tasks {
      if let index = all.firstIndex(where: { $0.id == task.id }) {
        positions[task.id] = index
      }
    }
    return positions.isEmpty ? nil : positions
  }

  /// Removes a trashed record and its media for good. The trash entry leaves the
  /// store first; the files are only removed once that write landed, so a failed
  /// write can never lose the attachments while the entry is still there.
  func permanentlyDeleteTrashedRecord(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = trashedRecords.firstIndex(where: { $0.id == id }) else { return }

    var candidate = trashedRecords
    let record = candidate.remove(at: index)
    let additions = pendingDeletions(for: record.meeting)
    let deletions = pendingMediaDeletions + additions
    let stored = persistBatch {
      [
        (key: StorageKey.trash, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(deletions))
      ]
    }
    guard stored else { return }

    trashedRecords = candidate
    pendingMediaDeletions = deletions
    retryPendingMediaDeletions(onlyIDs: Set(additions.map(\.id)))
  }

  /// Removes media for records that are already gone from the store. A file that
  /// cannot be removed is remembered and retried, so this never fails in a way
  /// that could only be noticed later.
  func deleteMedia(audioURL: URL?, photoNames: [String]) {
    guard !isStoreProtected else { return }
    var remainingPhotos: [String] = []
    let referencedPhotos = referencedPhotoFileNames
    for name in photoNames where !referencedPhotos.contains(name) && !MediaFiles.deletePhoto(name) {
      remainingPhotos.append(name)
    }
    // Keep the managed reference, not the resolved path, so a retry after the
    // app container moves still finds the right file.
    var remainingAudio: String?
    if let audioURL, let reference = MediaFiles.reference(for: audioURL),
       !referencedAudioFileNames.contains(reference), !MediaFiles.delete(audioURL) {
      remainingAudio = MediaFiles.reference(for: audioURL)
    }

    guard remainingAudio != nil || !remainingPhotos.isEmpty else { return }
    pendingMediaDeletions.append(
      PendingMediaDeletion(id: UUID(), audioReference: remainingAudio, photoNames: remainingPhotos)
    )
    persistPendingMediaDeletions()
    deletionFailureMessage = "一部のメディアを削除できませんでした。次回の起動で再試行します。"
  }

  /// Tries the removals that failed before, keeping any that fail again.
  func retryPendingMediaDeletions(onlyIDs: Set<UUID>? = nil) {
    guard !isStoreProtected, !pendingMediaDeletions.isEmpty, onlyIDs?.isEmpty != true else { return }

    var remaining: [PendingMediaDeletion] = []
    var didFail = false
    let referenced = referencedAudioFileNames
    let referencedPhotos = referencedPhotoFileNames
    for deletion in pendingMediaDeletions {
      if let onlyIDs, !onlyIDs.contains(deletion.id) {
        remaining.append(deletion)
        continue
      }
      var photos: [String] = []
      for name in deletion.photoNames where !referencedPhotos.contains(name) && !MediaFiles.deletePhoto(name) {
        photos.append(name)
      }
      var audio: String?
      if let reference = deletion.audioReference,
         let url = MediaFiles.resolve(reference),
         let name = MediaFiles.reference(for: url), !referenced.contains(name),
         !MediaFiles.delete(url) {
        audio = reference
      }
      if audio != nil || !photos.isEmpty {
        didFail = true
        remaining.append(PendingMediaDeletion(id: deletion.id, audioReference: audio, photoNames: photos))
      }
    }
    guard persistNow(remaining, forKey: StorageKey.pendingMediaDeletions) else { return }
    pendingMediaDeletions = remaining
    if didFail {
      deletionFailureMessage = "一部のメディアを削除できませんでした。次回の起動で再試行します。"
    }
  }

  /// Drops trashed records once their recovery window has passed. The entries
  /// are removed from the store first and their files afterwards, so an
  /// interruption leaves either the entry or the files, never a missing file
  /// with the entry still present.
  func purgeExpiredTrash() {
    guard !isStoreProtected else { return }
    let cutoff = Date().addingTimeInterval(-TrashedRecord.lifetime)

    let expiredRecords = trashedRecords.filter { $0.deletedAt < cutoff }
    let expiredEntries = trashedLifeLogEntries.filter { $0.deletedAt < cutoff }
    guard !expiredRecords.isEmpty || !expiredEntries.isEmpty else { return }

    let candidateRecords = trashedRecords.filter { $0.deletedAt >= cutoff }
    let candidateEntries = trashedLifeLogEntries.filter { $0.deletedAt >= cutoff }
    let additions = expiredRecords.flatMap { record in
      pendingDeletions(for: record.meeting)
    }
      + expiredEntries.map { record in
        PendingMediaDeletion(id: UUID(), audioReference: nil, photoNames: record.entry.photoFileName.map { [$0] } ?? [])
      }
    let deletions = pendingMediaDeletions + additions
    let stored = persistBatch {
      var documents: [(key: String, data: Data)] = []
      if !expiredRecords.isEmpty {
        documents.append((key: StorageKey.trash, data: try RecordStore.encoded(candidateRecords)))
      }
      if !expiredEntries.isEmpty {
        documents.append((key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidateEntries)))
      }
      documents.append((key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(deletions)))
      return documents
    }
    guard stored else { return }

    if !expiredRecords.isEmpty {
      trashedRecords = candidateRecords
    }
    if !expiredEntries.isEmpty {
      trashedLifeLogEntries = candidateEntries
    }

    pendingMediaDeletions = deletions
    retryPendingMediaDeletions(onlyIDs: Set(additions.map(\.id)))
  }
}
