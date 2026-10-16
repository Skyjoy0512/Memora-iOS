import Foundation

extension MemoraModel {
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected, let record = meeting(id: id) else { return false }
    return RecordAccessPolicy.allows(record.effectivePrivacy, purpose: purpose)
  }

  var residentAccessRevision: String {
    recordAccessRevision(for: .automaticAgent)
  }

  func recordAccessRevision(for purpose: RecordAccessPolicy.Purpose) -> String {
    guard !isRestoring, !isStoreProtected else { return "" }
    let records = meetings.filter { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: purpose) }
      .map { "meeting:\($0.id):\($0.privacy.updatedAt.timeIntervalSince1970)" }
    let journal = lifeLogEntries.filter { allowsJournalAccess($0, purpose: purpose) }
      .map { "journal:\($0.id):\($0.privacy.updatedAt.timeIntervalSince1970)" }
    let taskRecords = tasks.filter { allowsTaskAccess($0, purpose: purpose) }.map { task in
      let privacy = task.privacy ?? task.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy }
      return "task:\(task.id):\(privacy?.updatedAt.timeIntervalSince1970 ?? 0)"
    }
    let value = (records + journal + taskRecords).sorted().joined(separator: ",")
    return AIRecordFingerprint.make(value) ?? ""
  }

  func privacy(for target: RecordPrivacyTarget) -> RecordPrivacy? {
    switch target {
    case .meeting(let id): return meeting(id: id)?.effectivePrivacy
    case .journal(let id):
      guard let entry = lifeLogEntries.first(where: { $0.id == id }) else { return nil }
      var result = RecordAccessPolicy.effectiveRelatedPrivacy(entry.privacy,
        parent: entry.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy })
      if !entry.personIDs.isEmpty { result.protect(.personal) }
      return result
    case .task(let id):
      guard let task = tasks.first(where: { $0.id == id }) else { return nil }
      let parent = task.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy }
      return task.privacy.map { RecordAccessPolicy.effectiveRelatedPrivacy($0, parent: parent) } ?? parent ?? RecordPrivacy()
    }
  }

  func minimumPrivacyClassification(for target: RecordPrivacyTarget) -> RecordPrivacy.Classification {
    switch target {
    case .meeting(let id): return meeting(id: id)?.minimumPrivacyClassification ?? .unknown
    case .journal(let id):
      guard let entry = lifeLogEntries.first(where: { $0.id == id }) else { return .unknown }
      let parent = entry.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy.classification } ?? .unknown
      let minimum: RecordPrivacy.Classification = entry.personIDs.isEmpty ? .unknown : .personal
      return parent.rank > RecordPrivacy.Classification.general.rank && parent.rank > minimum.rank ? parent : minimum
    case .task(let id):
      let classification = tasks.first { $0.id == id }?.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy.classification } ?? .unknown
      return classification.rank > RecordPrivacy.Classification.general.rank ? classification : .unknown
    }
  }

  func allowsRecordAccess(_ target: RecordPrivacyTarget, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected else { return false }
    switch target {
    case .meeting(let id): return allowsRecordAccess(id, purpose: purpose)
    case .journal(let id):
      guard let entry = lifeLogEntries.first(where: { $0.id == id }) else { return false }
      return allowsJournalAccess(entry, purpose: purpose)
    case .task(let id):
      guard let task = tasks.first(where: { $0.id == id }) else { return false }
      return allowsTaskAccess(task, purpose: purpose)
    }
  }

  func setRecordPrivacy(_ privacy: RecordPrivacy, target: RecordPrivacyTarget) async -> Bool {
    if case .meeting(let id) = target { return await setRecordPrivacy(privacy, meetingID: id) }
    guard !isRestoring, isStoreWritable(), privacy.classification.rank >= minimumPrivacyClassification(for: target).rank else { return false }
    var updated = privacy
    updated.updatedAt = .now
    if !supportsWebhookPermission(target) { updated.allowsAutomaticWebhook = false }
    if !supportsTeamPermission(target) { updated.allowsTeamSharing = false }
    switch target {
    case .meeting: return false
    case .journal(let id):
      guard let index = lifeLogEntries.firstIndex(where: { $0.id == id }),
            AIJournalPrivacy.allowsReading(kind: lifeLogEntries[index].kind, origin: lifeLogEntries[index].origin) else { return false }
      var candidate = lifeLogEntries
      candidate[index].privacy = updated
      guard persistNow(candidate, forKey: StorageKey.lifeLogEntries) else { return false }
      lifeLogEntries = candidate
    case .task(let id):
      guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
      var candidate = tasks
      candidate[index].privacy = updated
      guard persistNow(candidate, forKey: StorageKey.tasks) else { return false }
      tasks = candidate
    }
    return true
  }

  func cloudReadingIsAvailable(for target: RecordPrivacyTarget) -> Bool {
    guard case .journal(let id) = target else { return privacy(for: target) != nil }
    guard let entry = lifeLogEntries.first(where: { $0.id == id }) else { return false }
    return AIJournalPrivacy.allowsReading(kind: entry.kind, origin: entry.origin)
  }

  func supportsWebhookPermission(_ target: RecordPrivacyTarget) -> Bool {
    switch target {
    case .meeting: return true
    case .task(let id): return tasks.first { $0.id == id }?.meetingID != nil
    case .journal: return false
    }
  }

  func supportsTeamPermission(_ target: RecordPrivacyTarget) -> Bool {
    switch target {
    case .meeting: return true
    case .task(let id): return tasks.first { $0.id == id }?.meetingID != nil
    case .journal(let id): return lifeLogEntries.first { $0.id == id }?.meetingID != nil
    }
  }

  func permittedTasks(for purpose: RecordAccessPolicy.Purpose, scope: AIChatScope) -> [MemoraTask] {
    guard !isRestoring, !isStoreProtected else { return [] }
    let parents = Set(Self.meetings(in: scope, from: meetings).map(\.id))
    return tasks.filter { task in
      (task.meetingID.map(parents.contains) ?? (scope == .all))
        && allowsTaskAccess(task, purpose: purpose)
    }
  }

  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected else { return false }
    return RecordAccessPolicy.allowsRelated(task.privacy, parentID: task.meetingID,
      parentPrivacy: task.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy }, purpose: purpose, inheritsParent: true)
  }

  func allowsJournalAccess(_ entry: LifeLogEntry, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected, AIJournalPrivacy.allowsReading(kind: entry.kind, origin: entry.origin) else { return false }
    var privacy = entry.privacy
    if !entry.personIDs.isEmpty { privacy.protect(.personal) }
    return RecordAccessPolicy.allowsRelated(privacy, parentID: entry.meetingID,
      parentPrivacy: entry.meetingID.flatMap { meeting(id: $0)?.effectivePrivacy }, purpose: purpose)
  }

  func setRecordPrivacy(_ privacy: RecordPrivacy, meetingID: UUID) async -> Bool {
    guard !isRestoring, isStoreWritable(), let record = meeting(id: meetingID) else { return false }
    var updated = privacy
    guard updated.classification.rank >= record.minimumPrivacyClassification.rank else { return false }
    updated.updatedAt = .now
    guard updateMeeting(meetingID, change: { $0.privacy = updated }) else { return false }
    guard await persistNowAsync(meetings, forKey: StorageKey.meetings) else {
      if meeting(id: meetingID)?.privacy == updated { updateMeeting(meetingID) { $0.privacy = record.privacy } }
      return false
    }
    return true
  }
}
