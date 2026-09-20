import Foundation

// People: creating, tagging, and looking up the people attached to records.
extension MemoraModel {

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
    meetings.filter { ($0.participantIDs ?? []).contains(personID) }.count
  }

  func meetings(withPerson personID: UUID) -> [Meeting] {
    meetings
      .filter { ($0.participantIDs ?? []).contains(personID) }
      .sorted { $0.createdAt > $1.createdAt }
  }
}
