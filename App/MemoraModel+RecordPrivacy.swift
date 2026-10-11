import Foundation

extension MemoraModel {
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    guard !isRestoring, !isStoreProtected, let record = meeting(id: id) else { return false }
    return RecordAccessPolicy.allows(record.effectivePrivacy, purpose: purpose)
  }

  var residentAccessRevision: String {
    meetings.filter { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: .automaticAgent) }
      .map { "\($0.id):\($0.privacy.updatedAt.timeIntervalSince1970)" }.sorted().joined(separator: ",")
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
