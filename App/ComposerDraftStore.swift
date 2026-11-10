import Foundation

@MainActor
enum ComposerDraftStore {
  static let questionKey = "composer.question"
  static let mentionsKey = "composer.mentions"
  static let attachmentKey = "composer.attachment.v1"
  static let recoveryIndexKey = "draft.composer.recovery.index.v1"
  private static let keys = [questionKey, mentionsKey, attachmentKey]

  enum Failure: Error, Equatable {
    case unreadable
    case unavailable
    case archiveUnreadable
  }

  static func load() throws -> ComposerDraftSnapshot {
    try snapshot(from: readFields(), strict: true)
  }

  /// Archive and replacement share the same SQLite transaction. Earlier queued
  /// draft writes settle first; no suspension can introduce a newer input here.
  static func recover() throws -> ComposerDraftSnapshot {
    let fields = try readFields()
    do { return try snapshot(from: fields, strict: true) }
    catch Failure.unreadable {}
    let restored = try snapshot(from: fields, strict: false)
    let archive = ComposerDraftRecoveryArchive(reference: .init(), fields: fields)
    var references = try recoveryArchives()
    references.insert(archive.reference, at: 0)
    var writes: [(key: String, data: Data)] = [
      (archiveKey(archive.reference.id), try RecordStore.encoded(archive)),
      (recoveryIndexKey, try RecordStore.encoded(references)),
      (DraftStore.storageKey(for: questionKey), DraftStore.encode(restored.question)),
      (DraftStore.storageKey(for: mentionsKey), DraftStore.encode(String(decoding: try JSONEncoder().encode(restored.mentions), as: UTF8.self))),
    ]
    var removing = [String]()
    if let attachment = restored.attachment {
      writes.append((DraftStore.storageKey(for: attachmentKey), DraftStore.encode(String(decoding: try JSONEncoder().encode(attachment), as: UTF8.self))))
    } else { removing.append(DraftStore.storageKey(for: attachmentKey)) }
    try RecordStore.commitNow(writes: writes, removing: removing)
    return restored
  }

  static func recoveryArchives() throws -> [ComposerDraftRecoveryArchive.Reference] {
    switch RecordStore.load(recoveryIndexKey) {
    case .absent: return []
    case .failed: throw Failure.unavailable
    case .data(let data):
      guard let references = try? JSONDecoder().decode([ComposerDraftRecoveryArchive.Reference].self, from: data),
            Set(references.map(\.id)).count == references.count,
            references.allSatisfy({ $0.createdAt.timeIntervalSince1970.isFinite }) else { throw Failure.archiveUnreadable }
      return references
    }
  }

  static func archiveData(_ reference: ComposerDraftRecoveryArchive.Reference) throws -> Data {
    guard case .data(let data) = RecordStore.load(archiveKey(reference.id)),
          let archive = try? JSONDecoder().decode(ComposerDraftRecoveryArchive.self, from: data),
          archive.version == 1, archive.reference == reference,
          Set(archive.fields.keys).isSubset(of: Set(keys)) else { throw Failure.archiveUnreadable }
    return data
  }

  private static func archiveKey(_ id: UUID) -> String { "draft.composer.recovery." + id.uuidString }

  private static func readFields() throws -> [String: Data] {
    var fields: [String: Data] = [:]
    for key in keys {
      switch RecordStore.loadLatestData(DraftStore.storageKey(for: key)) {
      case .absent: break
      case .failed: throw Failure.unavailable
      case .data(let data): fields[key] = data
      }
    }
    return fields
  }

  private static func snapshot(from fields: [String: Data], strict: Bool) throws -> ComposerDraftSnapshot {
    func text(_ key: String) throws -> String? {
      guard let bytes = fields[key] else { return nil }
      if let value = DraftStore.decode(bytes) { return value }
      if strict { throw Failure.unreadable }
      return nil
    }
    var result = ComposerDraftSnapshot(question: try text(questionKey) ?? "")
    if let value = try text(mentionsKey) {
      if let mentions = try? JSONDecoder().decode([ComposerMention].self, from: Data(value.utf8)) {
        result.mentions = mentions.filter { $0.isValid(in: result.question) }
      } else if strict { throw Failure.unreadable }
    }
    if let value = try text(attachmentKey) {
      if let reference = try? JSONDecoder().decode(AIAttachmentFileReference.self, from: Data(value.utf8)), reference.isValid {
        result.attachment = reference
      } else if strict { throw Failure.unreadable }
    }
    return result
  }
}
