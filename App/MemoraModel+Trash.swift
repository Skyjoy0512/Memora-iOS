import Foundation

extension MemoraModel {
  /// Moves a record to the trash. Its audio, tasks, and journal entries are kept
  /// so it can be restored exactly, and removed only when the trash is emptied.
  /// The lists are only changed once the write lands, so a failed save leaves
  /// the screen showing what the store actually holds.
  func deleteMeeting(_ id: UUID) {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return }
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
    let stored = persistBatch(meetings: candidateMeetings) {
      [
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
        self?.restoreTrashedRecord(trashID, preservingPosition: true) ?? false
      } finalize: {}
    )
  }

  /// Moves several records to the trash in one write, so a multi-selection
  /// either lands completely or not at all. Each record keeps its own tasks and
  /// journal entries so it can be restored exactly.
  func deleteMeetings(_ ids: Set<UUID>) {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return }
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

    let stored = persistBatch(meetings: candidateMeetings) {
      [
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
        self?.restoreTrashedRecords(Set(trashIDs), preservingPosition: true) ?? false
      } finalize: {}
    )
  }

  /// Puts a trashed record back exactly as it was, again only after the write.
  /// The saved position is only used when `preservingPosition` is set, which is
  /// the undo path; a restore from the trash days later goes back by date, since
  /// records added meanwhile would have made the old index wrong.
  @discardableResult
  func restoreTrashedRecord(_ id: UUID, preservingPosition: Bool = false) -> Bool {
    restoreTrashedRecords([id], preservingPosition: preservingPosition)
  }

  /// The entire undo batch commits together, including attached tasks and journal entries.
  @discardableResult
  func restoreTrashedRecords(_ ids: Set<UUID>, preservingPosition: Bool = false) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), !ids.isEmpty else { return false }
    let records = trashedRecords.filter { ids.contains($0.id) }
    let available = Set(records.map(\.id)).union(meetings.map(\.id))
    guard ids.isSubset(of: available) else {
      deletionFailureMessage = "ごみ箱に復元する記録が見つかりませんでした。"
      return false
    }
    guard !records.isEmpty else { return true }
    let restoredTasks = records.flatMap(\.tasks)
    let restoredEntries = records.flatMap(\.lifeLogEntries)
    guard Set(records.map(\.id)).count == records.count,
          Set(restoredTasks.map(\.id)).count == restoredTasks.count,
          Set(restoredEntries.map(\.id)).count == restoredEntries.count,
          Set(records.map(\.id)).isDisjoint(with: meetings.map(\.id)),
          Set(restoredTasks.map(\.id)).isDisjoint(with: tasks.map(\.id)),
          Set(restoredEntries.map(\.id)).isDisjoint(with: lifeLogEntries.map(\.id)) else {
      deletionFailureMessage = "同じIDの項目があるため、上書きせずに復元を止めました。"
      return false
    }
    var candidateMeetings = meetings
    let ordered = records.enumerated().sorted { lhs, rhs in
      if preservingPosition { return (lhs.element.meetingPosition ?? lhs.offset) < (rhs.element.meetingPosition ?? rhs.offset) }
      return lhs.element.meeting.createdAt > rhs.element.meeting.createdAt
    }.map(\.element)
    for record in ordered {
      let datePosition = candidateMeetings.firstIndex { $0.createdAt < record.meeting.createdAt } ?? candidateMeetings.count
      let position = preservingPosition ? (record.meetingPosition ?? datePosition) : datePosition
      candidateMeetings.insert(record.meeting, at: min(max(0, position), candidateMeetings.count))
    }
    let positions = preservingPosition
      ? records.reduce(into: [UUID: Int]()) { $0.merge($1.taskPositions ?? [:]) { first, _ in first } } : [:]
    let orderedTasks = restoredTasks.enumerated().sorted {
      (positions[$0.element.id] ?? $0.offset) < (positions[$1.element.id] ?? $1.offset)
    }.map(\.element)
    var candidateTasks = tasks
    for (offset, task) in orderedTasks.enumerated() {
      candidateTasks.insert(task, at: min(max(0, positions[task.id] ?? offset), candidateTasks.count))
    }
    let candidateEntries = lifeLogEntries + restoredEntries
    let candidateTrash = trashedRecords.filter { !ids.contains($0.id) }
    guard persistBatch(meetings: candidateMeetings, { [
      (key: StorageKey.tasks, data: try RecordStore.encoded(candidateTasks)),
      (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
      (key: StorageKey.trash, data: try RecordStore.encoded(candidateTrash))
    ] }) else { return false }
    trashedRecords = candidateTrash
    meetings = candidateMeetings
    tasks = candidateTasks
    lifeLogEntries = candidateEntries
    return true
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
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return }
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
    guard !isRestoring, currentTeamID == nil, !isStoreProtected else { return }
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
    guard !isRestoring, !isStoreProtected, !pendingMediaDeletions.isEmpty, onlyIDs?.isEmpty != true else { return }

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
    guard !isRestoring, currentTeamID == nil, !isStoreProtected else { return }
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
