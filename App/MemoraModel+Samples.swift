import Foundation

extension MemoraModel {
  /// Adds the display samples, used only when the person chooses them from
  /// onboarding (or reloads them from the debug settings). Real records are not
  /// touched, but the debug reload replaces the current set by design.
  func loadSampleContent() {
    let sample = SampleContent.make()
    meetings = sample.meetings
    spaces = sample.spaces
    lifeLogEntries = SampleContent.makeLifeLog()
    tasks = sample.tasks
    people = SampleContent.makePeople()
    aiHistory = [Self.seedAIHistoryEntry()]
    aiMessages = []
    persistMeetings()
    persistSpaces()
    persistLifeLog()
    persistTasks()
    persistPeople()
    persistAIHistory()
    homePath = []
    libraryPath = []
    // The samples are mostly recordings, and this matches the tab the app now
    // opens on, so "サンプルで見る" lands where the samples are.
    selectedTab = .files
  }

  /// Removes the display samples for good, without putting them in the trash.
  /// Only records the samples own are removed; everything the person made,
  /// including tasks and journal entries that point at a real record, stays.
  func deleteSampleContent() {
    guard isStoreWritable() else { return }

    let keptMeetings = meetings.filter { !SampleContent.isSample(meetingID: $0.id) }
    let keptSpaces = spaces.filter { !SampleContent.isSample(spaceID: $0.id) }
    let keptTasks = tasks.filter { !SampleContent.isSample(task: $0) }
    let keptLifeLog = lifeLogEntries.filter { !SampleContent.isSample(lifeLogEntry: $0) }
    // A sample person stays if a record the person made still points at them, so
    // deleting the samples never leaves a real record with a missing participant.
    let referencedPeople = Set(keptMeetings.compactMap(\.participantIDs).flatMap { $0 })
    let keptPeople = people.filter { person in
      !SampleContent.isSample(personID: person.id) || referencedPeople.contains(person.id)
    }
    let keptHistory = aiHistory.filter { $0.id != Self.seedAIHistoryID }

    let stored = persistBatch {
      [
        (key: StorageKey.meetings, data: try RecordStore.encoded(keptMeetings)),
        (key: StorageKey.spaces, data: try RecordStore.encoded(keptSpaces)),
        (key: StorageKey.tasks, data: try RecordStore.encoded(keptTasks)),
        (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(keptLifeLog)),
        (key: StorageKey.people, data: try RecordStore.encoded(keptPeople)),
        (key: StorageKey.aiHistory, data: try RecordStore.encoded(keptHistory))
      ]
    }
    guard stored else { return }

    meetings = keptMeetings
    spaces = keptSpaces
    tasks = keptTasks
    lifeLogEntries = keptLifeLog
    people = keptPeople
    aiHistory = keptHistory
    // A route left pointing at a removed sample would open an empty screen.
    homePath.removeAll { route in
      if case .meeting(let id) = route { return SampleContent.isSample(meetingID: id) }
      return false
    }
    libraryPath.removeAll { route in
      if case .meeting(let id) = route { return SampleContent.isSample(meetingID: id) }
      if case .space(let id) = route { return SampleContent.isSample(spaceID: id) }
      return false
    }
  }

  /// Queues the one-time offer to clear the samples after a real save. A
  /// recording's offer waits for its sheet to close; the flag is only recorded
  /// when the person answers, so an offer that never appeared can still be made.
  func noteRealSaveForSampleCleanup() {
    guard isSampleCleanupOfferEligible else { return }
    pendingSampleCleanupSuggestion = true
  }

  /// Shows a queued offer, once the screen that produced it has settled.
  func presentPendingSampleCleanupIfNeeded() {
    let eligible = pendingSampleCleanupSuggestion && isSampleCleanupOfferEligible
    pendingSampleCleanupSuggestion = false
    guard eligible else { return }
    isSampleCleanupSuggested = true
  }

  /// Records that the person answered the offer, so it is not made again.
  func completeSampleCleanupSuggestion() {
    UserDefaults.standard.set(true, forKey: StorageKey.hasOfferedSampleDeletion)
    isSampleCleanupSuggested = false
  }

  private var isSampleCleanupOfferEligible: Bool {
    !UserDefaults.standard.bool(forKey: StorageKey.hasOfferedSampleDeletion) && hasSampleContent
  }

  func removeAllContent() {
    meetings = []
    lifeLogEntries = []
    persistLifeLog()
    tasks = []
    persistTasks()
    people = []
    persistPeople()
    aiHistory = []
    aiMessages = []
    spaces = []
    persistMeetings()
    persistSpaces()
    homePath = []
    libraryPath = []
  }

#if DEBUG
  /// The prefix the synthetic records used for measurements carry, so they can
  /// be recognised and removed again.
  static let measurementTitlePrefix = "計測用レコード "

  /// Adds numbered records so launch, search, and save can be measured at the
  /// sizes the review asks about (100 / 1,000). They hold no audio, no summary,
  /// and no transcript — only a label and a date.
  func addMeasurementRecords(_ count: Int) {
    let existing = meetings.filter { $0.title.hasPrefix(Self.measurementTitlePrefix) }.count
    // Built aside and assigned once: inserting one by one rebuilt every derived
    // index per record, which made the 1,000 case take minutes.
    var added: [Meeting] = []
    var addedTasks: [MemoraTask] = []
    for offset in 0..<count {
      let meeting = Meeting(
        id: UUID(),
        title: "\(Self.measurementTitlePrefix)\(existing + offset + 1)",
        createdAt: .now.addingTimeInterval(-Double(offset) * 60),
        duration: 60,
        source: .importFile,
        status: .ready,
        summary: "",
        keyPoints: [],
        decisions: [],
        openQuestions: [],
        transcript: []
      )
      added.append(meeting)
      // One task each, so a long task list can be measured too.
      addedTasks.append(MemoraTask(
        id: UUID(),
        title: "計測用タスク \(existing + offset + 1)",
        meetingID: meeting.id,
        assignee: offset.isMultiple(of: 3) ? "Speaker 1" : nil,
        dueDate: offset.isMultiple(of: 4) ? .now.addingTimeInterval(Double(offset % 14) * 86_400) : nil,
        isCompleted: false
      ))
    }
    meetings.insert(contentsOf: added.reversed(), at: 0)
    tasks.insert(contentsOf: addedTasks, at: 0)
    persistMeetings()
    persistTasks()
  }

  func removeMeasurementRecords() {
    let removed = Set(meetings.filter { $0.title.hasPrefix(Self.measurementTitlePrefix) }.map(\.id))
    meetings.removeAll { removed.contains($0.id) }
    tasks.removeAll { $0.meetingID.map(removed.contains) ?? false }
    persistMeetings()
    persistTasks()
  }
#endif

  /// The one sample conversation shown before anything else exists. It has a
  /// fixed id so it can be told apart from real history when deciding whether
  /// the device is empty.
  static let seedAIHistoryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

  /// The one sample chat exchange shown with the samples, with the same fixed id
  /// so it can be removed with them.
  static func seedAIHistoryEntry() -> AIConversationEntry {
    AIConversationEntry(
      id: seedAIHistoryID,
      question: "今週決まったことは？",
      answer: "録音開始の速さを最優先にし、会議データは既定で端末内に保存する方針です。",
      scopeLabel: "すべての会話",
      createdAt: Calendar.current.date(byAdding: .hour, value: -4, to: .now)!
    )
  }
}
