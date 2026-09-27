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
    removingDraft draftKey: String? = nil
  ) -> Bool {
    // A restore is putting records in place; adding one now could be replaced.
    guard !isRestoring else { return false }
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

    lifeLogEntries.insert(
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
        locationName: trimmedLocation
      ),
      at: 0
    )
    // The entry and the draft removal land together when the caller asked for
    // one, so leaving the draft behind cannot happen beside a stored memo.
    return persistBatch({
      [(key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(lifeLogEntries))]
    }, removing: draftKey.map { [$0] } ?? [])
  }

  func updateLifeLogEntry(_ id: UUID, title: String, summary: String, createdAt: Date) {
    guard isStoreWritable() else { return }
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return }
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return }

    lifeLogEntries[index].title = trimmedTitle
    lifeLogEntries[index].summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    lifeLogEntries[index].createdAt = createdAt
    persistLifeLog()
  }

  /// Moves an entry to the trash, as one write, and only then changes the lists.
  func deleteLifeLogEntry(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }) else { return }

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
    guard stored else { return }

    lifeLogEntries = candidateEntries
    trashedLifeLogEntries = candidateTrash

    let trashID = candidateTrash[0].id
    scheduleUndo(
      UndoAction(message: "「\(removed.title)」を削除しました") { [weak self] in
        self?.restoreTrashedLifeLogEntry(trashID)
      } finalize: {}
    )
  }

  /// Moves several journal entries to the trash in one write, with one undo, so
  /// deleting a whole journey can be taken back as a whole.
  func deleteLifeLogEntries(_ ids: Set<UUID>) {
    guard isStoreWritable() else { return }
    guard !ids.isEmpty else { return }

    let removed = lifeLogEntries.filter { ids.contains($0.id) }
    guard !removed.isEmpty else { return }

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
    guard stored else { return }

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
    let stored = persistBatch {
      [(key: StorageKey.lifeLogTrash, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }

    trashedLifeLogEntries = candidate
    deleteMedia(
      audioURL: nil,
      photoNames: record.entry.photoFileName.map { [$0] } ?? []
    )
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
