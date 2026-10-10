import Foundation

enum ProjectFiling {
  static func records(in spaceID: UUID?, from meetings: [Meeting]) -> [Meeting] {
    meetings.filter { $0.spaceID == spaceID }
  }

  static func existingProject(_ spaceID: UUID?, in spaces: [MemoraSpace]) -> UUID? {
    guard let spaceID, spaces.contains(where: { $0.id == spaceID }) else { return nil }
    return spaceID
  }

  static func moving(_ ids: Set<UUID>, to spaceID: UUID?, meetings: [Meeting], spaces: [MemoraSpace]) -> [Meeting]? {
    guard !ids.isEmpty, ids.isSubset(of: Set(meetings.map(\.id))),
          spaceID == nil || existingProject(spaceID, in: spaces) != nil else { return nil }
    return meetings.map { meeting in
      guard ids.contains(meeting.id) else { return meeting }
      var moved = meeting
      moved.spaceID = spaceID
      return moved
    }
  }
}
