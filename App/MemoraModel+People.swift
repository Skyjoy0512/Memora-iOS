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
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let contactIdentifier,
       let existing = people.first(where: { $0.contactIdentifier == contactIdentifier }) {
      return existing
    }

    let person = Person(id: UUID(), name: trimmed, note: nil, contactIdentifier: contactIdentifier)
    people.append(person)
    persistPeople()
    return person
  }

  /// Renames a person and follows the change through to the tasks that used the
  /// old name, so no task is left pointing at a name nobody has.
  func updatePerson(_ id: UUID, name: String, note: String?) {
    guard let index = people.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let oldName = people[index].name
    let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    people[index].name = trimmed
    people[index].note = (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
    persistPeople()

    guard people.filter({ Self.isSameName($0.name, oldName) }).isEmpty,
          oldName.compare(trimmed, options: .caseInsensitive) != .orderedSame else { return }
    var changed = false
    for taskIndex in tasks.indices {
      guard let assignee = tasks[taskIndex].assignee,
            assignee.compare(oldName, options: .caseInsensitive) == .orderedSame else { continue }
      tasks[taskIndex].assignee = trimmed
      changed = true
    }
    if changed {
      persistTasks()
    }
  }

  /// Merges a duplicate into the person to keep: their tags and task assignments
  /// move over, then the duplicate is removed. Recordings are never deleted.
  func mergePerson(_ source: UUID, into target: UUID) {
    guard source != target,
          let targetIndex = people.firstIndex(where: { $0.id == target }),
          let sourceIndex = people.firstIndex(where: { $0.id == source }) else { return }

    let sourceName = people[sourceIndex].name
    let targetName = people[targetIndex].name

    // Keep a photo rather than losing it to the duplicate.
    if people[targetIndex].photoData == nil {
      people[targetIndex].photoData = people[sourceIndex].photoData
    }

    var meetingsChanged = false
    for index in meetings.indices {
      guard var ids = meetings[index].participantIDs, ids.contains(source) else { continue }
      ids.removeAll { $0 == source }
      if !ids.contains(target) {
        ids.append(target)
      }
      meetings[index].participantIDs = ids.isEmpty ? nil : ids
      meetingsChanged = true
    }
    if meetingsChanged {
      persistMeetings()
    }

    if people.filter({ Self.isSameName($0.name, sourceName) }).count == 1,
       sourceName.compare(targetName, options: .caseInsensitive) != .orderedSame {
      var tasksChanged = false
      for index in tasks.indices {
        guard let assignee = tasks[index].assignee,
              assignee.compare(sourceName, options: .caseInsensitive) == .orderedSame else { continue }
        tasks[index].assignee = targetName
        tasksChanged = true
      }
      if tasksChanged {
        persistTasks()
      }
    }

    people.removeAll { $0.id == source }
    persistPeople()
  }

  func setPersonPhoto(_ id: UUID, data: Data?) {
    guard let index = people.firstIndex(where: { $0.id == id }) else { return }
    people[index].photoData = data
    persistPeople()
  }

  func deletePerson(_ id: UUID) {
    people.removeAll { $0.id == id }
    persistPeople()
    for index in meetings.indices {
      meetings[index].participantIDs?.removeAll { $0 == id }
    }
    persistMeetings()
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
    meetingsByPerson[personID] ?? []
  }

  /// Participant tags establish a relationship; speaker-name similarity alone cannot.
  func memory(of personID: UUID) -> PersonMemory? {
    guard let person = person(id: personID) else { return nil }
    let name = person.name
    let uniqueName = people.filter { Self.isSameName($0.name, name) }.count == 1

    let tagged = Set(meetings(withPerson: personID).map(\.id))
    let related = meetings
      .filter { meeting in
        tagged.contains(meeting.id)
      }
      .sorted { $0.createdAt > $1.createdAt }
    let relatedIDs = Set(related.map(\.id))

    let open = tasks.filter { !$0.isCompleted }
    let assigned = open.filter { task in
      uniqueName && (task.assignee.map { Self.isSameName($0, name) } ?? false)
    }
    let assignedIDs = Set(assigned.map(\.id))
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
    let journal = uniqueName && name.count >= 2
      ? newestLifeLogEntries.filter { $0.title.contains(name) || $0.summary.contains(name) }
      : []

    return PersonMemory(
      person: person,
      meetings: related,
      assignedTasks: assigned,
      sharedTasks: shared,
      decisions: Array(decisions),
      journalEntries: Array(journal.prefix(20))
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
