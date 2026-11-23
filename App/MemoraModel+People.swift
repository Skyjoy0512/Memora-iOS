import Foundation

// People: creating, tagging, and looking up the people attached to records.
extension MemoraModel {
  func person(id: UUID) -> Person? {
    personIndex.element(id, in: people)
  }

  func persistPeople() {
    persistInBackground(people, forKey: StorageKey.people)
  }

  @discardableResult
  func addPerson(name: String, contactIdentifier: String? = nil) -> Person? {
    guard currentTeamID == nil, !isRestoring, isStoreWritable() else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let contactIdentifier,
       let existing = people.first(where: { $0.contactIdentifier == contactIdentifier }) {
      return existing
    }

    let person = Person(id: UUID(), name: trimmed, note: nil, contactIdentifier: contactIdentifier)
    var candidate = people
    candidate.append(person)
    guard persistNow(candidate, forKey: StorageKey.people) else { return nil }
    people = candidate
    return person
  }

  @discardableResult
  func updatePerson(_ id: UUID, name: String, note: String?) -> Bool {
    guard !isRestoring, currentTeamID == nil, let index = people.firstIndex(where: { $0.id == id }) else { return false }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    var updatedPeople = people
    updatedPeople[index].name = trimmed
    let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    updatedPeople[index].note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
    if updatedPeople[index].name != people[index].name || updatedPeople[index].note != people[index].note {
      updatedPeople[index].privacy = people[index].effectivePrivacy
      updatedPeople[index].privacy.revokeExternalPermissions()
    }
    var updatedTasks = tasks
    for index in updatedTasks.indices {
      let task = updatedTasks[index]
      if task.relationships.assigneePersonID == id, task.assignee != trimmed {
        updatedTasks[index].assignee = trimmed
        updatedTasks[index].privacy = taskPrivacyAfterPersonChange(task)
      }
    }
    guard persistBatch({ [
      (key: StorageKey.people, data: try RecordStore.encoded(updatedPeople)),
      (key: StorageKey.tasks, data: try RecordStore.encoded(updatedTasks))
    ] }) else { return false }
    people = updatedPeople; tasks = updatedTasks
    return true
  }

  /// User-confirmed merges move ID links together with tags in the same commit.
  @discardableResult
  func mergePerson(_ source: UUID, into target: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, source != target,
          let targetIndex = people.firstIndex(where: { $0.id == target }),
          let sourceIndex = people.firstIndex(where: { $0.id == source }) else { return false }
    let targetName = people[targetIndex].name
    var updatedPeople = people
    if updatedPeople[targetIndex].photoData == nil { updatedPeople[targetIndex].photoData = updatedPeople[sourceIndex].photoData }
    updatedPeople[targetIndex].privacy = people[targetIndex].effectivePrivacy
    updatedPeople[targetIndex].privacy.revokeExternalPermissions()
    updatedPeople.removeAll { $0.id == source }
    var updatedMeetings = meetings
    for index in updatedMeetings.indices {
      guard let ids = updatedMeetings[index].participantIDs, ids.contains(source) else { continue }
      updatedMeetings[index].participantIDs = Array(Set(ids.map { $0 == source ? target : $0 })).sorted { $0.uuidString < $1.uuidString }
    }
    var updatedTasks = tasks
    for index in updatedTasks.indices {
      let task = updatedTasks[index]
      if task.relationships.assigneePersonID == source {
        updatedTasks[index].relationships.assigneePersonID = target
        updatedTasks[index].privacy = taskPrivacyAfterPersonChange(task)
        updatedTasks[index].assignee = targetName
      }
    }
    var updatedJournal = lifeLogEntries
    for index in updatedJournal.indices {
      let entry = updatedJournal[index]
      guard entry.personIDs.contains(source) else { continue }
      updatedJournal[index].personIDs = Array(Set(entry.personIDs.map { $0 == source ? target : $0 }))
        .sorted { $0.uuidString < $1.uuidString }
      updatedJournal[index].privacy = journalPrivacyAfterPersonChange(entry)
    }
    guard persistBatch({ [
      (key: StorageKey.people, data: try RecordStore.encoded(updatedPeople)),
      (key: StorageKey.tasks, data: try RecordStore.encoded(updatedTasks)),
      (key: StorageKey.meetings, data: try RecordStore.encoded(updatedMeetings)),
      (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(updatedJournal))
    ] }) else { return false }
    people = updatedPeople; tasks = updatedTasks; meetings = updatedMeetings; lifeLogEntries = updatedJournal
    return true
  }

  @discardableResult
  func setPersonPhoto(_ id: UUID, data: Data?) -> Bool {
    guard currentTeamID == nil, !isRestoring, isStoreWritable(),
          let index = people.firstIndex(where: { $0.id == id }) else { return false }
    var candidate = people
    candidate[index].photoData = data
    guard persistNow(candidate, forKey: StorageKey.people) else { return false }
    people = candidate
    return true
  }

  @discardableResult
  func deletePerson(_ id: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, person(id: id) != nil else { return false }
    let updatedPeople = people.filter { $0.id != id }
    var updatedMeetings = meetings
    for index in updatedMeetings.indices { updatedMeetings[index].participantIDs?.removeAll { $0 == id } }
    guard persistBatch({ [
      (key: StorageKey.people, data: try RecordStore.encoded(updatedPeople)),
      (key: StorageKey.meetings, data: try RecordStore.encoded(updatedMeetings))
    ] }) else { return false }
    // Retain task/journal IDs so a new person with the same name cannot inherit them.
    people = updatedPeople; meetings = updatedMeetings
    return true
  }

  func toggleParticipant(personID: UUID, meeting meetingID: UUID) {
    guard let index = meetings.firstIndex(where: { $0.id == meetingID }) else { return }
    var ids = meetings[index].participantIDs ?? []
    if let existing = ids.firstIndex(of: personID) {
      ids.remove(at: existing)
    } else {
      ids.append(personID)
    }
    meetings[index].participantIDs = ids.isEmpty ? nil : ids
    persistMeetings()
  }

  func participants(in meetingID: UUID) -> [Person] {
    let ids = meeting(id: meetingID)?.participantIDs ?? []
    return people.filter { ids.contains($0.id) }
  }

  func meetingCount(forPerson personID: UUID) -> Int {
    personMeetingCounts[personID] ?? 0
  }

  func meetings(withPerson personID: UUID) -> [Meeting] {
    (meetingIndicesByPerson[personID] ?? []).compactMap { position in
      meetings.indices.contains(position) ? meetings[position] : nil
    }
  }

  /// Participant tags establish a relationship; speaker-name similarity alone cannot.
  func memory(of personID: UUID) -> PersonMemory? {
    guard let person = person(id: personID) else { return nil }
    let name = person.name
    let normalizedName = PersonIdentity.normalized(name)
    let uniqueName = people.filter { PersonIdentity.normalized($0.name) == normalizedName }.count == 1

    let tagged = Set(meetings(withPerson: personID).map(\.id))
    let related = meetings
      .filter { meeting in
        tagged.contains(meeting.id)
      }
      .sorted { $0.createdAt > $1.createdAt }
    let relatedIDs = Set(related.map(\.id))

    let open = tasks.filter { !$0.isCompleted }
    let assigned = open.filter { PersonTaskAssociation.isAssigned($0, to: personID) }
    let nameMatched = open.filter { PersonTaskAssociation.nameMatches($0, normalizedName: normalizedName, isUnique: uniqueName) }
    let assignedIDs = Set((assigned + nameMatched).map(\.id))
    let shared = open.filter { task in
      guard !assignedIDs.contains(task.id), let meetingID = task.meetingID else { return false }
      return relatedIDs.contains(meetingID)
    }

    let decisions = related.prefix(12).flatMap { meeting in
      meeting.decisions.prefix(3).map {
        PersonMemory.Decision(meetingID: meeting.id, meetingTitle: meeting.displayTitle, date: meeting.createdAt, text: $0)
      }
    }

    // A short name matches too much of ordinary text, so the journal is only
    // searched for names of two characters or more.
    let entries = newestLifeLogEntries
    let journal = entries.filter { $0.personIDs.contains(personID) }
    let nameMatchedJournal = uniqueName && normalizedName.count >= 2
      ? entries.filter { $0.personIDs.isEmpty && PersonIdentity.normalized($0.title + " " + $0.summary).contains(normalizedName) }
      : []

    return PersonMemory(
      person: person,
      meetings: related,
      assignedTasks: assigned,
      sharedTasks: shared,
      decisions: Array(decisions),
      journalEntries: Array(journal.prefix(20)),
      nameMatchedTasks: nameMatched,
      nameMatchedJournalEntries: Array(nameMatchedJournal.prefix(20))
    )
  }

  /// Finds a person by name the way people refer to each other: 「田中さん」
  /// matches 田中, and a full name matches its family name.
  func person(named query: String) -> Person? {
    PersonIdentity.uniqueMatch(for: query, in: people)
  }

  static func isSameName(_ lhs: String, _ rhs: String) -> Bool {
    PersonIdentity.normalized(lhs) == PersonIdentity.normalized(rhs)
  }
}
