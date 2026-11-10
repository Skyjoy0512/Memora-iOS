import Foundation

extension MemoraModel {
  func recoverComposerDraft() throws {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, !isAIChatResponding,
          composerDraftFailure == .unreadable else { throw ComposerDraftStore.Failure.unavailable }
    let recovered = try ComposerDraftStore.recover()
    // Keep writes blocked while applying all fields from the same repaired snapshot.
    composerDraft = recovered.question
    composerMentions = recovered.mentions
    composerAttachment = recovered.attachment?.resolve()
    composerDraftFailure = nil
  }
}
