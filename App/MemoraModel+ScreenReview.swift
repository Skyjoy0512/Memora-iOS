import Foundation

extension MemoraModel {
  @discardableResult
  func addScreenReviewSamples() -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    let sampleMeetings = ScreenReviewSamples.meetings()
    let unavailableIDs = Set(meetings.map(\.id) + trashedRecords.map(\.id))
    let addedMeetings = sampleMeetings.filter { !unavailableIDs.contains($0.id) }
    let nextMeetings = addedMeetings + meetings
    let nextSpaces = addingMissing([MemoraSpace(id: ScreenReviewSamples.spaceID,
      name: "画面確認（サンプル）", symbol: "folder")], to: spaces)
    let nextPeople = addingMissing([Person(id: ScreenReviewSamples.personID,
      name: "田中（サンプル）", note: "画面確認用の架空の人物です。", contactIdentifier: nil)], to: people)
    let presentIDs = Set(nextMeetings.map(\.id))
    let nextTasks = addingMissing(ScreenReviewSamples.tasks().filter {
      $0.meetingID.map(presentIDs.contains) ?? false
    }, to: tasks)
    let nextJournal = addingMissing(ScreenReviewSamples.journal(for: sampleMeetings).filter {
      $0.meetingID.map(presentIDs.contains) ?? false
    }, to: lifeLogEntries)
    let nextDocuments = addingMissing(ScreenReviewSamples.documents(), to: documents)
    let nextHistory = addingMissing([ScreenReviewSamples.history()], to: aiHistory)
    guard persistBatch({ [
      (key: StorageKey.meetings, data: try RecordStore.encoded(nextMeetings)),
      (key: StorageKey.spaces, data: try RecordStore.encoded(nextSpaces)),
      (key: StorageKey.people, data: try RecordStore.encoded(nextPeople)),
      (key: StorageKey.tasks, data: try RecordStore.encoded(nextTasks)),
      (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(nextJournal)),
      (key: StorageKey.documents, data: try RecordStore.encoded(nextDocuments)),
      (key: StorageKey.aiHistory, data: try RecordStore.encoded(nextHistory))
    ] }) else { return false }
    meetings = nextMeetings
    spaces = nextSpaces
    people = nextPeople
    tasks = nextTasks
    lifeLogEntries = nextJournal
    documents = nextDocuments
    aiHistory = nextHistory
    selectedTab = .library
    librarySection = .files
    libraryPath = []
    return true
  }

  private func addingMissing<Item: Identifiable>(_ samples: [Item], to existing: [Item]) -> [Item] {
    let ids = Set(existing.map(\.id))
    return samples.filter { !ids.contains($0.id) } + existing
  }
}
