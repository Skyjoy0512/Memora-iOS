import Foundation

extension MemoraModel {
  /// Brings the photo entries in line with the records: a photo a record holds is
  /// indexed, one no record holds any more is dropped, and metadata that does
  /// not match the file is read again. The files are never changed here.
  @discardableResult
  func reconcileMediaIndex() -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected else { return false }
    var owners: [String: Meeting] = [:]
    for record in meetings {
      for name in record.photoFileNames ?? [] {
        owners[name] = owners[name] ?? record
      }
    }
    var updated = mediaIndexEntries.filter { owners[$0.name] != nil }
    for (name, record) in owners {
      let byteCount = MediaFiles.byteCount(ofPhotoNamed: name) ?? 0
      if let index = updated.firstIndex(where: { $0.name == name }) {
        updated[index].recordID = record.id
        updated[index].recordTitle = record.displayTitle
        updated[index].recordDate = record.createdAt
        if updated[index].byteCount != byteCount {
          updated[index].byteCount = byteCount
          let size = MediaFiles.pixelSize(ofPhotoNamed: name)
          updated[index].pixelWidth = size?.width ?? 0
          updated[index].pixelHeight = size?.height ?? 0
        }
      } else {
        let size = MediaFiles.pixelSize(ofPhotoNamed: name)
        updated.append(MediaIndexEntry(
          name: name, recordID: record.id, recordTitle: record.displayTitle,
          recordDate: record.createdAt, byteCount: byteCount,
          pixelWidth: size?.width ?? 0, pixelHeight: size?.height ?? 0))
      }
    }
    updated.sort { $0.recordDate == $1.recordDate ? $0.name < $1.name : $0.recordDate > $1.recordDate }
    updated = Array(updated.prefix(MediaIndexEntry.maximumEntries))
    guard updated != mediaIndexEntries else { return true }
    guard persistNow(updated, forKey: MediaIndexEntry.storageKey) else { return false }
    mediaIndexEntries = updated
    return true
  }

  /// Reads the words in photos that have not been read yet, a bounded number per
  /// visit. A read that fails stays unread, so it is tried again later instead of
  /// being recorded as empty.
  @discardableResult
  func readPendingMediaText(limit: Int = 30) async -> Int {
    guard currentTeamID == nil, !isRestoring, isStoreWritable(), !isStoreProtected else { return 0 }
    let pending = mediaIndexEntries.filter { $0.textReadAt == nil }.prefix(limit)
    guard !pending.isEmpty else { return 0 }
    var entries = mediaIndexEntries
    var read = 0
    for entry in pending {
      if Task.isCancelled { break }
      guard let text = await MediaTextRecognizer.read(photoNamed: entry.name),
            let index = entries.firstIndex(where: { $0.name == entry.name }) else { continue }
      entries[index].text = String(text.prefix(MediaIndexEntry.maximumText))
      entries[index].textReadAt = .now
      read += 1
    }
    guard read > 0, persistNow(entries, forKey: MediaIndexEntry.storageKey) else { return 0 }
    mediaIndexEntries = entries
    return read
  }

  /// The entries by photo name, for the screen that shows them.
  func mediaEntriesByName() -> [String: MediaIndexEntry] {
    Dictionary(mediaIndexEntries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
  }
}
