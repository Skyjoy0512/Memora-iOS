import Foundation

extension MemoraModel {
  func draftEmailTool(_ call: AgentToolCall, messageID: UUID) async -> AgentToolOutcome {
    guard let message = agentMessage(messageID) else { return Self.declinedOutcome }
    let workspaceID = currentTeamID
    let provenance = artifactProvenance(for: message)
    let personIDs = aiPersonScopeID.map { [$0] } ?? []
    let subject = AnswerCitations.stripped(call.string("subject")).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = AnswerCitations.stripped(call.string("body")).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else {
      return AgentToolOutcome(text: "本文が空です。", isError: true)
    }
    // Only addresses are kept; a name alone cannot be sent to.
    let recipients = call.strings("to")
    let cc = call.strings("cc"), bcc = call.strings("bcc")
    guard (recipients + cc + bcc).allSatisfy(MailDraft.validAddress) else {
      return AgentToolOutcome(text: "宛先は確認済みのメールアドレスだけにしてください。不明なら空欄にします。", isError: true)
    }

    var lines = ["件名: \(subject.isEmpty ? "（なし）" : subject)"]
    if !recipients.isEmpty { lines.append("宛先: \(recipients.joined(separator: ", "))") }
    lines.append(String(body.prefix(160)))
    guard let stepID = await approve(
      tool: .draftEmail,
      title: "メールの下書きを端末に保存",
      lines: lines,
      confirmTitle: "開く",
      messageID: messageID
    ) else { return Self.declinedOutcome }

    guard artifactCreationIsCurrent(messageID: messageID, workspaceID: workspaceID, provenance: provenance),
          pluginCallIsPermitted(call, messageID: messageID) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "参照情報または権限が変更されました")
      return AgentToolOutcome(text: "参照情報または権限が変わったため、下書き保存を止めました。送信していません。", isError: true)
    }

    var draft = MailDraft(recipients: recipients, subject: subject, body: body, cc: cc, bcc: bcc)
    draft.workspaceID = workspaceID; draft.personIDs = personIDs
    draft.provenance = provenance
    draft.sourceMessageID = messageID; draft.recordIDs = message.sources.map(\.meetingID)
    let projects = Set(draft.recordIDs.compactMap { meeting(id: $0)?.spaceID })
    draft.projectID = projects.count == 1 ? projects.first : nil
    guard saveMailDraft(draft) else {
      finishAgentStep(stepID, on: messageID, state: .failed, detail: "下書きを保存できませんでした")
      return AgentToolOutcome(text: "下書きの保存に失敗しました。送信していません。", isError: true)
    }
    pendingMailDraft = draft
    finishAgentStep(stepID, on: messageID, state: .done, detail: subject)
    return AgentToolOutcome(text: "下書きを開きました。送信するかどうかは利用者が決めます。")
  }
}
