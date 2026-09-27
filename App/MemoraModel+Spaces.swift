import Foundation

extension MemoraModel {
  func addSpace(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    spaces.insert(MemoraSpace(id: UUID(), name: trimmed, symbol: "folder"), at: 0)
    persistSpaces()
  }

  func renameSpace(_ id: UUID, name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
    spaces[index].name = trimmed
    persistSpaces()
  }

  /// Removes a project. Its records are kept and become uncategorized.
  func deleteSpace(_ id: UUID) {
    guard spaces.contains(where: { $0.id == id }) else { return }
    spaces.removeAll { $0.id == id }
    persistSpaces()

    for index in meetings.indices where meetings[index].spaceID == id {
      meetings[index].spaceID = nil
    }
    persistMeetings()
  }

  /// Files a record under a project, or takes it out of every project.
  func setSpace(_ spaceID: UUID?, forMeeting meetingID: UUID) {
    updateMeeting(meetingID) { $0.spaceID = spaceID }
  }

  /// Files several records under one project, or under none, in a single write.
  func moveMeetings(_ ids: Set<UUID>, to spaceID: UUID?) {
    guard !isStoreProtected else {
      blockProtectedChanges()
      return
    }
    guard !ids.isEmpty else { return }

    var candidate = meetings
    var changed = false
    for index in candidate.indices where ids.contains(candidate[index].id) {
      guard candidate[index].spaceID != spaceID else { continue }
      candidate[index].spaceID = spaceID
      meetingSearchTexts.removeValue(forKey: candidate[index].id)
      changed = true
    }
    guard changed else { return }

    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return }
    meetings = candidate
  }
}
