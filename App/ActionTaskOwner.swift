import Foundation

/// Decides whether a summary action is the person's own, using the voice the
/// record was matched to rather than the words the summary chose for the owner.
enum ActionTaskOwner {
  enum Ownership: Equatable {
    case mine
    case other
    /// The registered voice is in the record and the summary credited the action
    /// to the person, but its wording does not point at one speaker, so the
    /// person decides instead of the name rule guessing.
    case needsConfirmation

    var ownedByMe: Bool? {
      switch self {
      case .mine: true
      case .other: false
      case .needsConfirmation: nil
      }
    }
  }

  /// `nil` keeps the existing name-based rule. A verified voice only decides an
  /// action the summary already credited to the person.
  static func ownership(owner: String?, names: [String], actionTitle: String,
                        transcript: [TranscriptSegment], ownSpeakerID: String?) -> Ownership? {
    guard let ownSpeakerID, !ownSpeakerID.isEmpty,
          let owner, TaskOwnership.namesSelf(owner, names: names) else { return nil }
    guard let speakerID = ActionSpeakerMatch.speakerID(forAction: actionTitle, in: transcript) else {
      return .needsConfirmation
    }
    return TaskOwnership.speakerOwnership(speakerID: speakerID, ownSpeakerID: ownSpeakerID) == true
      ? .mine : .other
  }
}
