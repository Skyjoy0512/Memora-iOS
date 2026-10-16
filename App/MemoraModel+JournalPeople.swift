import Foundation

extension MemoraModel {
  /// Deleted IDs may survive an unrelated edit, but cannot be newly assigned.
  func journalPeopleAreValid(_ selected: Set<UUID>, retaining existing: Set<UUID> = []) -> Bool {
    selected.subtracting(existing).isSubset(of: Set(people.map(\.id)))
  }

  func journalPrivacyAfterPersonChange(_ entry: LifeLogEntry) -> RecordPrivacy {
    var result = privacy(for: .journal(entry.id)) ?? entry.privacy
    result.protect(.personal)
    result.revokeExternalPermissions()
    return result
  }
}
