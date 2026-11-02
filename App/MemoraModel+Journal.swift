import Foundation

extension MemoraModel {
  @discardableResult
  func addLifeLogEntry(
    id: UUID = UUID(),
    kind: LifeLogKind,
    title: String,
    summary: String,
    createdAt: Date,
    photoData: Data?,
    eventDate: Date?,
    locationName: String?,
    place: JournalPlace? = nil,
    personIDs: Set<UUID> = [],
    removingDraft draftKey: String? = nil
  ) -> Bool {
    // A restore is putting records in place; adding one now could be replaced.
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), journalPeopleAreValid(personIDs),
          personIDs.isEmpty || kind != .location else { return false }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedLocation = locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle: String
    if !trimmedTitle.isEmpty {
      resolvedTitle = trimmedTitle
    } else if kind == .location, let trimmedLocation, !trimmedLocation.isEmpty {
      resolvedTitle = "\(trimmedLocation)に到着"
    } else {
      resolvedTitle = kind.label
    }

    // Photos live in the media folder; the entry keeps the file name.
    let photoFileName = photoData.flatMap { MediaFiles.writePhoto($0, thumbnailMaxSide: 400) }
    guard photoData == nil || photoFileName != nil else { return false }

    var privacy = RecordPrivacy()
    if !personIDs.isEmpty { privacy.protect(.personal) }
    var candidate = lifeLogEntries
    candidate.insert(
      LifeLogEntry(
        id: id,
        createdAt: createdAt,
        title: resolvedTitle,
        summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
        source: .iphone,
        meetingID: nil,
        kind: kind,
        photoFileName: photoFileName,
        eventDate: eventDate,
        locationName: trimmedLocation,
        latitude: place?.latitude,
        longitude: place?.longitude,
        privacy: privacy,
        personIDs: personIDs.sorted { $0.uuidString < $1.uuidString }
      ),
      at: 0
    )
    // The entry and the draft removal land together when the caller asked for
    // one, so leaving the draft behind cannot happen beside a stored memo.
    let stored = persistBatch({
      [(key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidate))]
    }, removing: draftKey.map { [$0] } ?? [])
    guard stored else {
      if let photoFileName { _ = MediaFiles.deletePhoto(photoFileName) }
      return false
    }
    lifeLogEntries = candidate
    return true
  }

  @discardableResult
  func updateLifeLogEntry(_ id: UUID, title: String, summary: String, createdAt: Date,
                         locationName: String?, place: JournalPlace?, personIDs: Set<UUID>? = nil) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return false }
    let original = lifeLogEntries[index]
    let oldIDs = Set(original.personIDs)
    let selected = personIDs ?? oldIDs
    guard journalPeopleAreValid(selected, retaining: oldIDs),
          selected.isSubset(of: oldIDs) || AIJournalPrivacy.allowsReading(kind: original.kind, origin: original.origin) else { return false }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return false }

    var candidate = lifeLogEntries
    candidate[index].title = trimmedTitle
    candidate[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    candidate[index].personIDs = selected.sorted { $0.uuidString < $1.uuidString }
    if selected != oldIDs { candidate[index].privacy = journalPrivacyAfterPersonChange(original) }
    if candidate[index].kind == .location || candidate[index].kind == .event {
      let name = locationName?.trimmingCharacters(in: .whitespacesAndNewlines)
      candidate[index].locationName = name?.isEmpty == false ? name : nil
      candidate[index].latitude = place?.latitude
      candidate[index].longitude = place?.longitude
    }
    if candidate[index].eventDate != nil {
      candidate[index].eventDate = createdAt
    } else {
      candidate[index].createdAt = createdAt
    }
    guard persistBatch({ [(key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidate))] }) else {
      return false
    }
    lifeLogEntries = candidate
    return true
  }

  /// Moves an entry to the trash, as one write, and only then changes the lists.
  @discardableResult
  func deleteLifeLogEntry(_ id: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return false }

    var candidateEntries = lifeLogEntries
    var candidateTrash = trashedLifeLogEntries
    let removed = candidateEntries.remove(at: index)
    candidateTrash.insert(TrashedLifeLogEntry(entry: removed, deletedAt: .now), at: 0)

    let stored = persistBatch {
      [
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return false }

    lifeLogEntries = candidateEntries
    trashedLifeLogEntries = candidateTrash

    let trashID = candidateTrash[0].id
    scheduleUndo(
      UndoAction(message: "「\(removed.title)」を削除しました") { [weak self] in
        self?.restoreTrashedLifeLogEntry(trashID)
      } finalize: {}
    )
    return true
  }

  /// Moves several journal entries to the trash in one write, with one undo, so
  /// deleting a whole journey can be taken back as a whole.
  @discardableResult
  func deleteLifeLogEntries(_ ids: Set<UUID>) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), !ids.isEmpty else { return false }

    let removed = lifeLogEntries.filter { ids.contains($0.id) }
    guard !removed.isEmpty else { return false }

    var candidateEntries = lifeLogEntries
    var candidateTrash = trashedLifeLogEntries
    candidateEntries.removeAll { ids.contains($0.id) }
    candidateTrash.insert(contentsOf: removed.map { TrashedLifeLogEntry(entry: $0, deletedAt: .now) }, at: 0)

    let stored = persistBatch {
      [
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return false }

    lifeLogEntries = candidateEntries
    trashedLifeLogEntries = candidateTrash

    let trashIDs = candidateTrash.prefix(removed.count).map(\.id)
    scheduleUndo(
      UndoAction(message: "\(removed.count)件の記録を削除しました") { [weak self] in
        for id in trashIDs {
          self?.restoreTrashedLifeLogEntry(id)
        }
      } finalize: {}
    )
    return true
  }

  func restoreTrashedLifeLogEntry(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = trashedLifeLogEntries.firstIndex(where: { $0.id == id }) else { return }

    var candidateTrash = trashedLifeLogEntries
    let record = candidateTrash.remove(at: index)
    var candidateEntries = lifeLogEntries
    candidateEntries.append(record.entry)

    let stored = persistBatch {
      [
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidateEntries)),
        (key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidateTrash))
      ]
    }
    guard stored else { return }

    trashedLifeLogEntries = candidateTrash
    lifeLogEntries = candidateEntries
  }

  func permanentlyDeleteTrashedLifeLogEntry(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = trashedLifeLogEntries.firstIndex(where: { $0.id == id }) else { return }

    var candidate = trashedLifeLogEntries
    let record = candidate.remove(at: index)
    let deletion = PendingMediaDeletion(
      id: UUID(), audioReference: nil, photoNames: record.entry.photoFileName.map { [$0] } ?? []
    )
    let deletions = pendingMediaDeletions + [deletion]
    let stored = persistBatch {
      [
        (key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.pendingMediaDeletions, data: try RecordStore.encoded(deletions))
      ]
    }
    guard stored else { return }

    trashedLifeLogEntries = candidate
    pendingMediaDeletions = deletions
    retryPendingMediaDeletions(onlyIDs: [deletion.id])
  }

  /// Brings in journal records the automatic logger wrote while the model was
  /// not running. Records already present are skipped by id, and the inbox is
  /// cleared in the same write as the import, so nothing is taken twice.
  func importAutoLifeLogInbox() {
    guard !isStoreProtected else { return }
    guard case .data(let data) = RecordStore.load(StorageKey.autoLifeLogInbox),
          let inbox = try? JSONDecoder().decode([LifeLogEntry].self, from: data),
          !inbox.isEmpty else { return }

    let existing = Set(lifeLogEntries.map(\.id))
    let incoming = inbox.filter { !existing.contains($0.id) }
    var candidate = lifeLogEntries
    candidate.append(contentsOf: incoming)

    let stored = persistBatch {
      [
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(candidate)),
        (key: StorageKey.autoLifeLogInbox, data: try RecordStore.encoded([LifeLogEntry]()))
      ]
    }
    guard stored else { return }
    lifeLogEntries = candidate
  }
}
