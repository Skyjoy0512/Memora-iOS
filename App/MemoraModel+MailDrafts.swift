import Foundation

extension MemoraModel {
  @discardableResult
  func saveMailDraft(_ draft: MailDraft) -> Bool {
    guard !isRestoring, draft.workspaceID == currentTeamID, draft.body.count <= 100_000,
          draft.subject.count <= 500, draft.recipients.count + draft.cc.count + draft.bcc.count <= 100,
          (draft.recipients + draft.cc + draft.bcc).allSatisfy(MailDraft.validAddress), isStoreWritable() else { return false }
    var candidate = mailDrafts
    if let index = candidate.firstIndex(where: { $0.id == draft.id }) { candidate[index] = draft }
    else { guard candidate.count < 1_000 else { return false }; candidate.insert(draft, at: 0) }
    guard persistNow(candidate, forKey: "memora.mailDrafts.v1") else { return false }
    mailDrafts = candidate
    return true
  }

  @discardableResult
  func deleteMailDraft(_ id: UUID) -> Bool {
    let candidate = mailDrafts.filter { $0.id != id || $0.workspaceID != currentTeamID }
    guard !isRestoring, persistNow(candidate, forKey: "memora.mailDrafts.v1") else { return false }
    mailDrafts = candidate
    for field in ["body", "subject", "to", "cc", "bcc"] { DraftStore.clear("mail.\(id).\(field)") }
    return true
  }
}
