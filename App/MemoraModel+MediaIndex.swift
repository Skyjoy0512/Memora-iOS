import Foundation

extension MemoraModel {
  /// Brings the photo entries in line with the records: a photo a record holds is
  /// indexed, one no record holds any more is dropped, and metadata that does
  /// not match the file is read again. The files are never changed here.
  @discardableResult
  func reconcileMediaIndex() -> Bool {
    guard !Task.isCancelled, currentTeamID == nil, !isRestoring, !isStoreProtected else { return false }
    var owners: [String: Meeting] = [:]
    for record in meetings {
      for name in record.photoFileNames ?? [] {
        owners[name] = owners[name] ?? record
      }
    }
    let existing = mediaEntriesByName()
    let ordered = owners.sorted { lhs, rhs in
      lhs.value.createdAt == rhs.value.createdAt ? lhs.key < rhs.key : lhs.value.createdAt > rhs.value.createdAt
    }
    var updated: [MediaIndexEntry] = []
    for (name, record) in ordered {
      guard let file = Self.mediaIndexFileValues(named: name), let byteCount = file.fileSize else { continue }
      if var entry = existing[name], entry.recordID == record.id, entry.matchesOriginal(file) {
        entry.recordTitle = record.displayTitle
        entry.recordDate = record.createdAt
        updated.append(entry)
      } else {
        let size = MediaFiles.pixelSize(ofPhotoNamed: name)
        updated.append(MediaIndexEntry(
          name: name, recordID: record.id, recordTitle: record.displayTitle,
          recordDate: record.createdAt, byteCount: byteCount,
          fileModifiedAt: file.contentModificationDate,
          pixelWidth: size?.width ?? 0, pixelHeight: size?.height ?? 0))
      }
      if updated.count == MediaIndexEntry.maximumEntries { break }
    }
    guard updated != mediaIndexEntries else { return true }
    guard persistNow(updated, forKey: MediaIndexEntry.storageKey) else { return false }
    mediaIndexEntries = updated
    return true
  }

  /// Reads the words in photos that have not been read yet, a bounded number per
  /// visit. A read that fails stays unread, so it is tried again later instead of
  /// being recorded as empty.
  @discardableResult
  func readPendingMediaText(for photoNames: Set<String>? = nil, limit: Int = 30) async -> Int {
    let generation = aiWorkspaceGeneration
    guard limit > 0, mediaReadIsCurrent(generation) else { return 0 }
    let pending = mediaIndexEntries.lazy.filter {
      $0.textReadAt == nil && photoNames?.contains($0.name) != false
    }.prefix(limit)
    var results: [String: (original: MediaIndexEntry, text: String)] = [:]
    for entry in pending {
      guard mediaReadIsCurrent(generation) else { return 0 }
      guard mediaIndexEntryHasLiveOriginal(entry),
            let text = await MediaTextRecognizer.read(photoNamed: entry.name) else { continue }
      results[entry.name] = (entry, String(text.prefix(MediaIndexEntry.maximumText)))
    }
    guard mediaReadIsCurrent(generation), !results.isEmpty else { return 0 }

    // Recognition suspends while records and the index can change. Merge only
    // results that still refer to the same photo in the current workspace.
    var updated = mediaIndexEntries
    var read = 0
    for index in updated.indices {
      let entry = updated[index]
      guard entry.textReadAt == nil, let result = results[entry.name],
            entry.recordID == result.original.recordID,
            entry.byteCount == result.original.byteCount, entry.fileModifiedAt == result.original.fileModifiedAt,
            mediaIndexEntryHasLiveOriginal(entry) else { continue }
      updated[index].text = result.text
      updated[index].textReadAt = .now
      read += 1
    }
    guard read > 0, persistNow(updated, forKey: MediaIndexEntry.storageKey) else { return 0 }
    mediaIndexEntries = updated
    return read
  }

  private func mediaReadIsCurrent(_ generation: UUID) -> Bool {
    !Task.isCancelled && currentTeamID == nil && !isRestoring && !isStoreProtected &&
      aiWorkspaceGeneration == generation
  }

  /// A derived entry is only evidence while its record still owns the original.
  func mediaIndexEntryHasLiveOriginal(_ entry: MediaIndexEntry) -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected,
          meeting(id: entry.recordID)?.photoFileNames?.contains(entry.name) == true,
          let values = Self.mediaIndexFileValues(named: entry.name) else { return false }
    return entry.matchesOriginal(values)
  }

  /// Search already recognized text locally. Only matched candidates need a
  /// filesystem check before their owning records can appear in the results.
  func photoRecordIDs(matching query: String) -> Set<UUID> {
    guard CollectionSearch.hasQuery(query), currentTeamID == nil,
          !isRestoring, !isStoreProtected else { return [] }
    return Set(mediaIndexEntries.lazy.filter {
      $0.textReadAt != nil && CollectionSearch.matches(query, fields: [$0.text]) &&
        self.mediaIndexEntryHasLiveOriginal($0)
    }.map(\.recordID))
  }

  private static func mediaIndexFileValues(named name: String) -> URLResourceValues? {
    guard let url = MediaFiles.photoURL(name),
          let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey,
            .isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true, values.isSymbolicLink == false,
          values.contentModificationDate != nil else { return nil }
    return values
  }

  /// The entries by photo name, for the screen that shows them.
  func mediaEntriesByName() -> [String: MediaIndexEntry] {
    Dictionary(mediaIndexEntries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
  }
}
