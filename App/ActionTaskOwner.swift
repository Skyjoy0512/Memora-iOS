import Foundation

/// Decides whether a summary action is the person's own, using the voice the
/// record was matched to rather than the words the summary chose for the owner.
enum ActionTaskOwner {
  /// `nil` keeps the existing name-based rule. A verified voice only overrides
  /// it for an action the summary already credited to the person, and only when
  /// its wording points to one speaker clearly enough to attribute.
  static func ownedByMe(owner: String?, names: [String], actionTitle: String,
                        transcript: [TranscriptSegment], ownSpeakerID: String?) -> Bool? {
    guard let ownSpeakerID, !ownSpeakerID.isEmpty,
          let owner, TaskOwnership.namesSelf(owner, names: names),
          let speakerID = ActionSpeakerMatch.speakerID(forAction: actionTitle, in: transcript)
    else { return nil }
    return TaskOwnership.speakerOwnership(speakerID: speakerID, ownSpeakerID: ownSpeakerID)
  }
}
